-- Paigham v13: verified (blue tick) people, like official accounts on
-- Telegram. Only the server owner can give the tick, in this SQL Editor:
--
--   update profiles set verified = true where lower(email) = lower('someone@example.com');
--
-- Run once after v12.

alter table public.profiles add column if not exists verified boolean not null default false;

-- Nobody can give themselves the tick from the app (only the SQL Editor /
-- service role can change it).
create or replace function public.protect_verified() returns trigger
language plpgsql as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.verified := false;
    else
      new.verified := old.verified;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists protect_verified on public.profiles;
create trigger protect_verified before insert or update on public.profiles
  for each row execute function public.protect_verified();

-- my_chats: members carry the tick
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
                    'username', p.username, 'avatar_path', p.avatar_path, 'last_seen', p.last_seen, 'verified', p.verified,
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
