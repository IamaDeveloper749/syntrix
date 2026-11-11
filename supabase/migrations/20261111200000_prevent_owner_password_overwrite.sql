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
  if exists (
    select 1 from private.syntrix_owner_passwords
    where user_id = (select auth.uid())
  ) then
    raise exception 'Owner password is already set';
  end if;
  if p_password is null
     or length(p_password) < 12
     or octet_length(convert_to(p_password, 'UTF8')) > 72 then
    raise exception 'Password must be at least 12 characters and no more than 72 UTF-8 bytes';
  end if;

  insert into private.syntrix_owner_passwords
    (user_id, password_hash, failed_attempts, locked_until, updated_at)
  values
    ((select auth.uid()), extensions.crypt(p_password, extensions.gen_salt('bf', 12)), 0, null, now());

  return true;
end;
$$;