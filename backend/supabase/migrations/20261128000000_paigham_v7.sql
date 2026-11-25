-- Paigham v7: hearts on stories.
-- Run once in the Supabase SQL Editor after the v6 file.

alter table public.story_views add column if not exists liked boolean not null default false;

-- Like or unlike a story I can see (also counts as a view).
create or replace function public.like_story(s uuid, v boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if not exists (select 1 from stories st where st.id = s and st.expires_at > now()
                 and st.user_id <> auth.uid() and public.shares_chat(st.user_id)) then
    raise exception 'story not available';
  end if;
  insert into story_views (story_id, viewer_id, liked) values (s, auth.uid(), v)
  on conflict (story_id, viewer_id) do update set liked = excluded.liked;
end $$;
grant execute on function public.like_story(uuid, boolean) to authenticated;

-- Feed: each story says whether I liked it; my own stories carry their like count.
create or replace function public.story_feed() returns jsonb
language sql stable security definer set search_path = public as $$
  with visible as (
    select s.* from stories s
    where s.expires_at > now() and (s.user_id = auth.uid() or public.shares_chat(s.user_id))
  ), per_user as (
    select v.user_id,
           jsonb_agg(jsonb_build_object(
             'id', v.id, 'kind', v.kind, 'media_path', v.media_path, 'body', v.body, 'bg', v.bg,
             'created_at', v.created_at,
             'seen', exists (select 1 from story_views w where w.story_id = v.id and w.viewer_id = auth.uid()),
             'liked', exists (select 1 from story_views w where w.story_id = v.id and w.viewer_id = auth.uid() and w.liked),
             'views', case when v.user_id = auth.uid() then (select count(*) from story_views w where w.story_id = v.id) else null end,
             'likes', case when v.user_id = auth.uid() then (select count(*) from story_views w where w.story_id = v.id and w.liked) else null end
           ) order by v.created_at) as items,
           bool_and(exists (select 1 from story_views w where w.story_id = v.id and w.viewer_id = auth.uid())) as all_seen,
           max(v.created_at) as latest
    from visible v group by v.user_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user', jsonb_build_object('id', p.id, 'email', p.email, 'display_name', p.display_name,
                                      'username', p.username, 'avatar_path', p.avatar_path),
           'stories', u.items, 'all_seen', u.all_seen)
         order by (u.user_id = auth.uid()) desc, u.all_seen, u.latest desc), '[]'::jsonb)
  from per_user u join profiles p on p.id = u.user_id;
$$;

-- Viewers list of my story, with a heart for those who liked it.
create or replace function public.story_viewers(s uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'email', p.email, 'display_name', p.display_name,
                   'avatar_path', p.avatar_path, 'viewed_at', w.viewed_at, 'liked', w.liked)
                   order by w.liked desc, w.viewed_at desc), '[]'::jsonb)
  from story_views w join profiles p on p.id = w.viewer_id
  join stories st on st.id = w.story_id
  where w.story_id = s and st.user_id = auth.uid();
$$;
