-- Paigham v9: nothing readable even if the server is broken into.
-- Run once in the Supabase SQL Editor after the v8 file.
--
--  * stories: content and photos sealed on the phone; each viewer gets a
--    copy of the story key locked for them (story_keys),
--  * reactions: the emoji is sealed with the chat key,
--  * old messages from before v8: their sender's phone seals them and
--    deletes the old plain files (seal_old_message, attachments_delete_own).

-- ── Stories ─────────────────────────────────────────────────────────────────
alter table public.stories add column if not exists cipher text check (char_length(cipher) <= 4000);

create table if not exists public.story_keys (
  story_id  uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.profiles(id) on delete cascade,
  wrapped   text not null check (char_length(wrapped) < 200),
  primary key (story_id, viewer_id)
);
alter table public.story_keys enable row level security;
drop policy if exists story_keys_read on public.story_keys;
create policy story_keys_read on public.story_keys for select to authenticated using (viewer_id = auth.uid());
drop policy if exists story_keys_insert on public.story_keys;
create policy story_keys_insert on public.story_keys for insert to authenticated
  with check (
    exists (select 1 from stories s where s.id = story_id and s.user_id = auth.uid())
    and (viewer_id = auth.uid() or public.shares_chat(viewer_id))
  );

-- Who may see my stories (people I share a chat with), with their public keys.
create or replace function public.story_audience() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('user_id', k.user_id, 'public_key', k.public_key)), '[]'::jsonb)
  from user_keys k
  where k.user_id = auth.uid() or public.shares_chat(k.user_id);
$$;
revoke execute on function public.story_audience from anon;

-- Feed as in v7, plus the sealed content and my copy of each story key.
create or replace function public.story_feed() returns jsonb
language sql stable security definer set search_path = public as $$
  with visible as (
    select s.* from stories s
    where s.expires_at > now() and (s.user_id = auth.uid() or public.shares_chat(s.user_id))
  ), per_user as (
    select v.user_id,
           jsonb_agg(jsonb_build_object(
             'id', v.id, 'kind', v.kind, 'media_path', v.media_path, 'body', v.body, 'bg', v.bg,
             'cipher', v.cipher,
             'wrapped', (select k.wrapped from story_keys k where k.story_id = v.id and k.viewer_id = auth.uid()),
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

-- ── Reactions ───────────────────────────────────────────────────────────────
alter table public.message_reactions add column if not exists cipher text check (char_length(cipher) <= 400);
alter table public.message_reactions add column if not exists key_id integer;

-- ── Old plain messages ──────────────────────────────────────────────────────
-- The sender's phone replaces an old plain message with its sealed version
-- (and, for files, points it at the newly uploaded encrypted copy).
create or replace function public.seal_old_message(m uuid, new_cipher text, new_key_id integer, new_file_path text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(new_cipher, '')) = 0 or char_length(new_cipher) > 20000 then raise exception 'bad cipher'; end if;
  update messages
     set cipher = new_cipher, key_id = new_key_id, body = '', meta = null, file_name = null,
         mime_type = null, duration_ms = null,
         file_path = case when new_file_path is null then file_path else new_file_path end
   where id = m and sender_id = auth.uid() and cipher is null and deleted_at is null;
end $$;
revoke execute on function public.seal_old_message from anon;

-- Uploaders may delete their own attachment files (old plain copies, deleted messages).
drop policy if exists attachments_delete_own on storage.objects;
create policy attachments_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'attachments' and owner = auth.uid());
