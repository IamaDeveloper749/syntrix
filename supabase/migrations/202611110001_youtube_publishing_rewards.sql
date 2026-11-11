-- SYNTRIX YouTube publishing records and one-time Pro demo reward.
create table if not exists public.youtube_video_posts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  video_id text not null unique,
  posted_at timestamptz not null default now()
);
create index if not exists youtube_video_posts_user_id_idx on public.youtube_video_posts(user_id);

create table if not exists public.creator_pro_trials (
  user_id uuid primary key references auth.users(id) on delete cascade,
  started_at timestamptz not null default now(),
  expires_at timestamptz not null
);

alter table public.youtube_video_posts enable row level security;
alter table public.creator_pro_trials enable row level security;

drop policy if exists "Users can read their own verified YouTube posts" on public.youtube_video_posts;
create policy "Users can read their own verified YouTube posts"
  on public.youtube_video_posts for select to authenticated using (auth.uid() = user_id);

drop policy if exists "Users can read their own Pro demo" on public.creator_pro_trials;
create policy "Users can read their own Pro demo"
  on public.creator_pro_trials for select to authenticated using (auth.uid() = user_id);

revoke all on public.youtube_video_posts from anon, authenticated;
grant select on public.youtube_video_posts to authenticated;
revoke all on public.creator_pro_trials from anon, authenticated;
grant select on public.creator_pro_trials to authenticated;

create or replace function public.record_verified_youtube_upload(p_user_id uuid, p_video_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
  v_expires timestamptz;
begin
  if p_user_id is null or p_video_id is null or length(trim(p_video_id)) < 5 then
    raise exception 'Invalid upload record';
  end if;

  insert into public.youtube_video_posts(user_id, video_id)
  values (p_user_id, trim(p_video_id))
  on conflict (video_id) do nothing;

  select count(*)::integer into v_count
  from public.youtube_video_posts where user_id = p_user_id;

  if v_count >= 20 then
    insert into public.creator_pro_trials(user_id, expires_at)
    values (p_user_id, now() + interval '1 month')
    on conflict (user_id) do nothing;
  end if;

  select expires_at into v_expires
  from public.creator_pro_trials where user_id = p_user_id;

  return jsonb_build_object('verifiedVideoCount', v_count, 'proExpiresAt', v_expires);
end;
$$;

revoke all on function public.record_verified_youtube_upload(uuid, text) from public, anon, authenticated;
grant execute on function public.record_verified_youtube_upload(uuid, text) to service_role;
