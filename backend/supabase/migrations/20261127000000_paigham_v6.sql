-- Paigham v6: Saved Messages and per-person chat options
-- (pin chat, mute, mark unread, archive, clear history).
-- Run once in the Supabase SQL Editor after the v5 file.

-- A "Saved Messages" chat: a private chat whose only member is you.
alter table public.chats add column if not exists is_saved boolean not null default false;

-- Settings that belong to one person's view of a chat.
alter table public.chat_members add column if not exists pinned_at     timestamptz;
alter table public.chat_members add column if not exists muted         boolean not null default false;
alter table public.chat_members add column if not exists archived      boolean not null default false;
alter table public.chat_members add column if not exists marked_unread boolean not null default false;
alter table public.chat_members add column if not exists cleared_at    timestamptz;

-- Returns my Saved Messages chat, creating it the first time.
create or replace function public.saved_chat() returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select c.id into cid from chats c
    join chat_members m on m.chat_id = c.id and m.user_id = auth.uid()
    where c.is_saved limit 1;
  if cid is not null then return cid; end if;
  insert into chats (is_group, is_saved, created_by) values (false, true, auth.uid()) returning id into cid;
  insert into chat_members (chat_id, user_id, role) values (cid, auth.uid(), 'admin');
  return cid;
end $$;
grant execute on function public.saved_chat() to authenticated;

-- "Message yourself" opens Saved Messages instead of failing.
create or replace function public.start_direct_chat(other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null then raise exception 'invalid user'; end if;
  if other = auth.uid() then return public.saved_chat(); end if;
  select c.id into cid from chats c
    join chat_members a on a.chat_id = c.id and a.user_id = auth.uid()
    join chat_members b on b.chat_id = c.id and b.user_id = other
    where not c.is_group and not c.is_saved limit 1;
  if cid is not null then return cid; end if;
  insert into chats (is_group, created_by) values (false, auth.uid()) returning id into cid;
  insert into chat_members (chat_id, user_id) values (cid, auth.uid()), (cid, other);
  return cid;
end $$;

-- Chat list: adds the new per-person settings; "clear history" hides older messages for me only.
create or replace function public.my_chats() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r order by r->>'last_message_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', c.id, 'is_group', c.is_group, 'is_saved', c.is_saved, 'title', c.title, 'avatar_path', c.avatar_path,
      'pinned_message_id', c.pinned_message_id,
      'last_message_at', c.last_message_at, 'my_last_read_at', me.last_read_at,
      'pinned_at', me.pinned_at, 'muted', me.muted, 'archived', me.archived,
      'marked_unread', me.marked_unread, 'cleared_at', me.cleared_at,
      'members', (select jsonb_agg(jsonb_build_object(
                    'id', p.id, 'email', p.email, 'display_name', p.display_name,
                    'username', p.username, 'avatar_path', p.avatar_path,
                    'last_read_at', m.last_read_at, 'role', m.role))
                  from chat_members m join profiles p on p.id = m.user_id where m.chat_id = c.id),
      'last_message', (select to_jsonb(x) from (select * from messages where chat_id = c.id and deleted_at is null
                       and created_at > coalesce(me.cleared_at, '-infinity')
                       order by created_at desc limit 1) x),
      'unread', (select count(*) from messages where chat_id = c.id and deleted_at is null
                 and created_at > me.last_read_at and created_at > coalesce(me.cleared_at, '-infinity')
                 and sender_id <> auth.uid())
    ) as r
    from chats c join chat_members me on me.chat_id = c.id and me.user_id = auth.uid()
  ) t;
$$;
