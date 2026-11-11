create table if not exists public.creator_owner_pro_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.creator_owner_pro_access enable row level security;
revoke all on public.creator_owner_pro_access from anon, authenticated;
grant select on public.creator_owner_pro_access to authenticated;

drop policy if exists "Users can read their own owner Pro status" on public.creator_owner_pro_access;
create policy "Users can read their own owner Pro status"
on public.creator_owner_pro_access
for select
to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.grant_syntrix_owner_pro()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if lower(coalesce(new.email, '')) = 'u2901624603@gmail.com' then
    insert into public.creator_owner_pro_access (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

revoke all on function public.grant_syntrix_owner_pro() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_grant_syntrix_owner_pro on auth.users;
create trigger on_auth_user_created_grant_syntrix_owner_pro
after insert on auth.users
for each row execute function public.grant_syntrix_owner_pro();

insert into public.creator_owner_pro_access (user_id)
select id from auth.users
where lower(coalesce(email, '')) = 'u2901624603@gmail.com'
on conflict (user_id) do nothing;
