create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
alter default privileges in schema private revoke all on tables from public, anon, authenticated;

create table if not exists private.syntrix_owner_passwords (
  user_id uuid primary key references auth.users(id) on delete cascade,
  password_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);
alter table private.syntrix_owner_passwords enable row level security;
revoke all on private.syntrix_owner_passwords from public, anon, authenticated;

create or replace function public.syntrix_owner_password_is_set()
returns boolean
language sql
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.creator_owner_pro_access o
    join private.syntrix_owner_passwords p on p.user_id = o.user_id
    where o.user_id = (select auth.uid())
  );
$$;

create or replace function public.set_syntrix_owner_password(p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in required';
  end if;
  if not exists (
    select 1 from public.creator_owner_pro_access
    where user_id = (select auth.uid())
  ) then
    raise exception 'Owner account only';
  end if;
  if p_password is null or length(p_password) < 12 or length(p_password) > 128 then
    raise exception 'Password must be between 12 and 128 characters';
  end if;

  insert into private.syntrix_owner_passwords
    (user_id, password_hash, failed_attempts, locked_until, updated_at)
  values
    ((select auth.uid()), extensions.crypt(p_password, extensions.gen_salt('bf', 12)), 0, null, now())
  on conflict (user_id) do update
    set password_hash = excluded.password_hash,
        failed_attempts = 0,
        locked_until = null,
        updated_at = now();

  return true;
end;
$$;

create or replace function public.verify_syntrix_owner_password(p_password text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hash text;
  v_failed integer;
  v_locked_until timestamptz;
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.creator_owner_pro_access
    where user_id = (select auth.uid())
  ) then
    return false;
  end if;

  select password_hash, failed_attempts, locked_until
    into v_hash, v_failed, v_locked_until
  from private.syntrix_owner_passwords
  where user_id = (select auth.uid())
  for update;

  if not found then
    return false;
  end if;
  if v_locked_until is not null and v_locked_until > now() then
    return false;
  end if;

  if p_password is not null and extensions.crypt(p_password, v_hash) = v_hash then
    update private.syntrix_owner_passwords
      set failed_attempts = 0, locked_until = null, updated_at = now()
      where user_id = (select auth.uid());
    return true;
  end if;

  v_failed := coalesce(v_failed, 0) + 1;
  update private.syntrix_owner_passwords
    set failed_attempts = case when v_failed >= 5 then 0 else v_failed end,
        locked_until = case when v_failed >= 5 then now() + interval '15 minutes' else null end,
        updated_at = now()
    where user_id = (select auth.uid());
  return false;
end;
$$;

revoke all on function public.syntrix_owner_password_is_set() from public, anon, authenticated;
revoke all on function public.set_syntrix_owner_password(text) from public, anon, authenticated;
revoke all on function public.verify_syntrix_owner_password(text) from public, anon, authenticated;
grant execute on function public.syntrix_owner_password_is_set() to authenticated;
grant execute on function public.set_syntrix_owner_password(text) to authenticated;
grant execute on function public.verify_syntrix_owner_password(text) to authenticated;