-- Replace the video-publishing reward with an automatic 21-day Pro trial.
-- Existing accounts receive a trial when this migration is applied.
-- New accounts receive a trial automatically after signup.

create or replace function public.handle_new_creator_trial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.creator_pro_trials (user_id, started_at, expires_at)
  values (new.id, now(), now() + interval '21 days')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_creator_trial() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_creator_trial on auth.users;
create trigger on_auth_user_created_creator_trial
  after insert on auth.users
  for each row execute function public.handle_new_creator_trial();

insert into public.creator_pro_trials (user_id, started_at, expires_at)
select id, now(), now() + interval '21 days'
from auth.users
on conflict (user_id) do update
set started_at = excluded.started_at,
    expires_at = excluded.expires_at;
