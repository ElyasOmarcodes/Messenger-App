-- Paigham v12: channels and the official "Paigham" channel (with a verified
-- tick), for announcing new features to everyone. Run once in the Supabase
-- SQL Editor after v11.
--
-- A channel is a group where only the owner and admins post. Its posts are
-- public announcements, so they are NOT end-to-end encrypted (like Telegram
-- channels); every private chat and group stays end-to-end encrypted.
-- Nobody can make a channel or a verified tick from the app: chats cannot be
-- updated by users (v10), only by these SQL statements.

alter table public.chats add column if not exists is_channel boolean not null default false;
alter table public.chats add column if not exists verified boolean not null default false;

-- ── The official channel ────────────────────────────────────────────────────
insert into public.chats (id, is_group, is_channel, verified, title, username, description, permissions)
values (
  '00000000-0000-4000-8000-000000000001', true, true, true,
  'پیغام', 'paigham',
  'د پیغام رسمي چینل: نوي بدلونونه او وړتیاوې.',
  '{"send": false, "media": false, "add": false, "pin": false, "info": false, "invite": true}'::jsonb
)
on conflict (id) do update set is_channel = true, verified = true;

-- everyone is subscribed; new people too (they can mute or leave)
insert into public.chat_members (chat_id, user_id, role)
select '00000000-0000-4000-8000-000000000001', p.id, 'member' from public.profiles p
on conflict do nothing;

create or replace function public.join_official_channel() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into chat_members (chat_id, user_id, role)
  values ('00000000-0000-4000-8000-000000000001', new.id, 'member')
  on conflict do nothing;
  return new;
exception when others then
  return new; -- never block a sign-up
end $$;

drop trigger if exists join_official_channel on public.profiles;
create trigger join_official_channel after insert on public.profiles
  for each row execute function public.join_official_channel();

-- Channel posts stay readable for every subscriber: never sealed with a
-- chat key (the app does not, and the server refuses it too).
create or replace function public.seal_old_message(m uuid, new_cipher text, new_key_id integer, new_file_path text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(new_cipher, '')) = 0 or char_length(new_cipher) > 20000 then raise exception 'bad cipher'; end if;
  if exists (select 1 from messages x join chats c on c.id = x.chat_id where x.id = m and c.is_channel) then return; end if;
  update messages
     set cipher = new_cipher, key_id = new_key_id, body = '', meta = null, file_name = null,
         mime_type = null, duration_ms = null,
         file_path = case when new_file_path is null then file_path else new_file_path end
   where id = m and sender_id = auth.uid() and cipher is null and deleted_at is null;
end $$;
revoke execute on function public.seal_old_message from anon;

-- ── my_chats: channel fields; a channel lists only its admins (not
-- thousands of subscribers) plus a subscriber count ─────────────────────────
create or replace function public.my_chats() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r order by r->>'last_message_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', c.id, 'is_group', c.is_group, 'is_saved', c.is_saved, 'title', c.title, 'avatar_path', c.avatar_path,
      'description', c.description, 'username', c.username, 'permissions', c.permissions,
      'is_channel', c.is_channel, 'verified', c.verified,
      'member_count', (select count(*) from chat_members x where x.chat_id = c.id),
      'pinned_message_id', c.pinned_message_id,
      'last_message_at', c.last_message_at, 'my_last_read_at', me.last_read_at,
      'pinned_at', me.pinned_at, 'muted', me.muted, 'archived', me.archived,
      'marked_unread', me.marked_unread, 'cleared_at', me.cleared_at,
      'members', (select jsonb_agg(jsonb_build_object(
                    'id', p.id, 'email', p.email, 'display_name', p.display_name,
                    'username', p.username, 'avatar_path', p.avatar_path, 'last_seen', p.last_seen,
                    'last_read_at', m.last_read_at, 'role', m.role, 'rights', m.rights)
                    order by (m.role = 'owner') desc, (m.role = 'admin') desc, m.joined_at)
                  from chat_members m join profiles p on p.id = m.user_id
                  where m.chat_id = c.id and (not c.is_channel or m.role <> 'member' or m.user_id = auth.uid())),
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

-- ── "typing…" ───────────────────────────────────────────────────────────────
-- Each person listens on their own private realtime channel "typing:<id>";
-- only people who share a chat with them may send to it. Nothing is stored.
drop policy if exists typing_listen on realtime.messages;
create policy typing_listen on realtime.messages for select to authenticated
  using (realtime.topic() = 'typing:' || auth.uid()::text and extension = 'broadcast');

drop policy if exists typing_send on realtime.messages;
create policy typing_send on realtime.messages for insert to authenticated
  with check (
    extension = 'broadcast'
    and realtime.topic() like 'typing:%'
    and exists (
      select 1 from public.chat_members a
      join public.chat_members b on b.chat_id = a.chat_id
      join public.chats c on c.id = a.chat_id and not c.is_channel
      where a.user_id = auth.uid()
        and b.user_id::text = substr(realtime.topic(), 8)
    )
  );
