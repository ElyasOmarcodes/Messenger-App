-- Paigham v0.5: edit, reactions, pinned messages, albums, location & contact
-- messages, group photos, and Stories (24-hour status).
-- Run once in the Supabase SQL Editor after the previous two files.

-- ── Messages: edit + rich kinds ────────────────────────────────────────────
alter table public.messages add column if not exists edited_at timestamptz;
alter table public.messages add column if not exists meta jsonb;  -- image size, album items, location, contact
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check
  check (kind in ('text', 'image', 'file', 'voice', 'album', 'location', 'contact'));

create or replace function public.edit_message(m uuid, new_body text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(new_body, '')) > 4000 then raise exception 'too long'; end if;
  update messages set body = new_body, edited_at = now()
  where id = m and sender_id = auth.uid() and deleted_at is null
    and kind in ('text', 'image', 'album', 'file');
end $$;
revoke execute on function public.edit_message from anon;

-- ── Reactions ──────────────────────────────────────────────────────────────
create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  chat_id    uuid not null references public.chats(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  emoji      text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);
create index if not exists reactions_chat on public.message_reactions (chat_id);
alter table public.message_reactions enable row level security;
alter table public.message_reactions replica identity full;
create policy reactions_select on public.message_reactions for select to authenticated using (public.is_member(chat_id));
create policy reactions_insert on public.message_reactions for insert to authenticated
  with check (user_id = auth.uid() and public.is_member(chat_id));
create policy reactions_update on public.message_reactions for update to authenticated using (user_id = auth.uid());
create policy reactions_delete on public.message_reactions for delete to authenticated using (user_id = auth.uid());

-- ── Pinned message and group photo ─────────────────────────────────────────
alter table public.chats add column if not exists pinned_message_id uuid references public.messages(id) on delete set null;
alter table public.chats add column if not exists avatar_path text;

create policy avatars_group_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and public.is_member(((storage.foldername(name))[1])::uuid));

-- ── Stories ────────────────────────────────────────────────────────────────
create table if not exists public.stories (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('image', 'text')),
  media_path text,
  body       text not null default '' check (char_length(body) <= 700),
  bg         text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);
create index if not exists stories_user on public.stories (user_id, created_at);

create table if not exists public.story_views (
  story_id  uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

-- True when the current user shares any chat with `other`.
create or replace function public.shares_chat(other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_members a join chat_members b on a.chat_id = b.chat_id
                 where a.user_id = auth.uid() and b.user_id = other);
$$;

alter table public.stories     enable row level security;
alter table public.story_views enable row level security;
create policy stories_select on public.stories for select to authenticated
  using (user_id = auth.uid() or (expires_at > now() and public.shares_chat(user_id)));
create policy stories_insert on public.stories for insert to authenticated with check (user_id = auth.uid());
create policy stories_delete on public.stories for delete to authenticated using (user_id = auth.uid());

create policy views_insert on public.story_views for insert to authenticated
  with check (viewer_id = auth.uid() and exists (select 1 from stories s where s.id = story_id
              and s.expires_at > now() and public.shares_chat(s.user_id)));
create policy views_select on public.story_views for select to authenticated
  using (viewer_id = auth.uid() or exists (select 1 from stories s where s.id = story_id and s.user_id = auth.uid()));

insert into storage.buckets (id, name, public, file_size_limit)
values ('stories', 'stories', false, 20971520)  -- 20 MB
on conflict (id) do nothing;
create policy stories_files_read on storage.objects for select to authenticated
  using (bucket_id = 'stories' and (((storage.foldername(name))[1])::uuid = auth.uid()
         or public.shares_chat(((storage.foldername(name))[1])::uuid)));
create policy stories_files_write on storage.objects for insert to authenticated
  with check (bucket_id = 'stories' and ((storage.foldername(name))[1])::uuid = auth.uid());
create policy stories_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'stories' and ((storage.foldername(name))[1])::uuid = auth.uid());

-- Feed: me first, then people with active stories (unseen first).
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
             'views', case when v.user_id = auth.uid() then (select count(*) from story_views w where w.story_id = v.id) else null end
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
revoke execute on function public.story_feed from anon;

create or replace function public.story_viewers(s uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'email', p.email, 'display_name', p.display_name,
                   'avatar_path', p.avatar_path, 'viewed_at', w.viewed_at) order by w.viewed_at desc), '[]'::jsonb)
  from story_views w join profiles p on p.id = w.viewer_id
  join stories st on st.id = w.story_id
  where w.story_id = s and st.user_id = auth.uid();
$$;
revoke execute on function public.story_viewers from anon;

-- Chat list now carries the group photo and pinned message.
create or replace function public.my_chats() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r order by r->>'last_message_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', c.id, 'is_group', c.is_group, 'title', c.title, 'avatar_path', c.avatar_path,
      'pinned_message_id', c.pinned_message_id,
      'last_message_at', c.last_message_at, 'my_last_read_at', me.last_read_at,
      'members', (select jsonb_agg(jsonb_build_object(
                    'id', p.id, 'email', p.email, 'display_name', p.display_name,
                    'username', p.username, 'avatar_path', p.avatar_path,
                    'last_read_at', m.last_read_at, 'role', m.role))
                  from chat_members m join profiles p on p.id = m.user_id where m.chat_id = c.id),
      'last_message', (select to_jsonb(x) from (select * from messages where chat_id = c.id and deleted_at is null
                       order by created_at desc limit 1) x),
      'unread', (select count(*) from messages where chat_id = c.id and deleted_at is null
                 and created_at > me.last_read_at and sender_id <> auth.uid())
    ) as r
    from chats c join chat_members me on me.chat_id = c.id and me.user_id = auth.uid()
  ) t;
$$;

alter publication supabase_realtime add table public.message_reactions, public.stories;
