-- Paigham v10: groups like Telegram — owner / admins with rights / members,
-- group permissions, remove and ban, invite links, public group links,
-- description. Run once in the Supabase SQL Editor after the v9 file.
--
-- Also closes two holes: members could make themselves admin (role was
-- updatable) and any member could change a group's details.

-- ── Roles and rights ────────────────────────────────────────────────────────
alter table public.chat_members drop constraint if exists chat_members_role_check;
alter table public.chat_members add constraint chat_members_role_check check (role in ('owner', 'admin', 'member'));
alter table public.chat_members add column if not exists rights jsonb;

-- the creator of each existing group becomes its owner
update public.chat_members m set role = 'owner'
  from public.chats c
 where c.id = m.chat_id and c.is_group and m.user_id = c.created_by and m.role = 'admin';

alter table public.chats add column if not exists description text check (char_length(description) <= 500);
alter table public.chats add column if not exists username text unique check (username ~ '^[a-z0-9_]{5,32}$');
-- what ordinary members may do
alter table public.chats add column if not exists permissions jsonb not null
  default '{"send": true, "media": true, "add": true, "pin": false, "info": false}'::jsonb;

-- Members may only change their own personal settings, never role or rights.
revoke update on public.chat_members from authenticated;
grant update (last_read_at, pinned_at, muted, archived, marked_unread, cleared_at) on public.chat_members to authenticated;
-- Group details change only through the functions below.
revoke update on public.chats from authenticated;

create table if not exists public.chat_bans (
  chat_id   uuid not null references public.chats(id) on delete cascade,
  user_id   uuid not null references public.profiles(id) on delete cascade,
  banned_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);
alter table public.chat_bans enable row level security;
drop policy if exists bans_read on public.chat_bans;
create policy bans_read on public.chat_bans for select to authenticated using (public.is_member(chat_id));

create table if not exists public.chat_invites (
  code        text primary key,
  chat_id     uuid not null references public.chats(id) on delete cascade,
  created_by  uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz,
  usage_limit integer check (usage_limit > 0),
  uses        integer not null default 0,
  revoked     boolean not null default false
);
alter table public.chat_invites enable row level security;
drop policy if exists invites_read on public.chat_invites;
create policy invites_read on public.chat_invites for select to authenticated using (public.is_member(chat_id));

-- May the caller do [what] in chat [c]?
--   owner: everything; admin: what their rights allow;
--   member: what the group's permissions allow; one-to-one chats: all but managing.
create or replace function public.can(c uuid, what text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  r text; rt jsonb; grp boolean; perms jsonb;
begin
  select m.role, m.rights into r, rt from chat_members m where m.chat_id = c and m.user_id = auth.uid();
  if r is null then return false; end if;
  select is_group, permissions into grp, perms from chats where id = c;
  if not grp then return what in ('send', 'media', 'pin', 'add'); end if;
  if r = 'owner' then return true; end if;
  if r = 'admin' then
    if what in ('send', 'media') then return true; end if;
    return coalesce((coalesce(rt, '{}'::jsonb) ->> what)::boolean,
                    what in ('info', 'delete', 'ban', 'invite', 'pin', 'add'));
  end if;
  return coalesce((perms ->> what)::boolean, false);
end $$;
revoke execute on function public.can from anon;

-- Sending checks the group's permissions too.
drop policy if exists messages_insert on public.messages;
create policy messages_insert on public.messages for insert to authenticated
  with check (
    sender_id = auth.uid() and public.is_member(chat_id) and public.can(chat_id, 'send')
    and (kind in ('text', 'location', 'contact') or public.can(chat_id, 'media'))
  );

-- ── Managing a group ────────────────────────────────────────────────────────
create or replace function public.update_group(c uuid, new_title text default null, new_description text default null, new_avatar_path text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can(c, 'info') then raise exception 'not allowed'; end if;
  update chats set
    title = coalesce(nullif(trim(new_title), ''), title),
    description = case when new_description is null then description else nullif(trim(new_description), '') end,
    avatar_path = coalesce(new_avatar_path, avatar_path)
  where id = c and is_group;
end $$;

create or replace function public.set_group_permissions(c uuid, perms jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can(c, 'ban') then raise exception 'not allowed'; end if;
  update chats set permissions = jsonb_build_object(
    'send', coalesce((perms ->> 'send')::boolean, true),
    'media', coalesce((perms ->> 'media')::boolean, true),
    'add', coalesce((perms ->> 'add')::boolean, true),
    'pin', coalesce((perms ->> 'pin')::boolean, false),
    'info', coalesce((perms ->> 'info')::boolean, false))
  where id = c and is_group;
end $$;

-- Make someone admin (with rights), or a member again. Owner, or admins
-- allowed to add admins; nobody can change the owner this way.
create or replace function public.set_member_role(c uuid, u uuid, new_role text, new_rights jsonb default null)
returns void
language plpgsql security definer set search_path = public as $$
declare me text; them text;
begin
  if new_role not in ('admin', 'member') then raise exception 'bad role'; end if;
  select role into me from chat_members where chat_id = c and user_id = auth.uid();
  select role into them from chat_members where chat_id = c and user_id = u;
  if them is null or them = 'owner' then raise exception 'not allowed'; end if;
  if not (me = 'owner' or (me = 'admin' and public.can(c, 'add_admins') and them = 'member')) then
    raise exception 'not allowed';
  end if;
  update chat_members set role = new_role, rights = case when new_role = 'admin' then new_rights else null end
   where chat_id = c and user_id = u;
end $$;

-- Remove a member (and, with ban, keep them out). Admins cannot remove
-- other admins; only the owner can.
create or replace function public.remove_member(c uuid, u uuid, ban boolean default false) returns void
language plpgsql security definer set search_path = public as $$
declare me text; them text;
begin
  select role into me from chat_members where chat_id = c and user_id = auth.uid();
  select role into them from chat_members where chat_id = c and user_id = u;
  if u = auth.uid() or them = 'owner' then raise exception 'not allowed'; end if;
  if not public.can(c, 'ban') then raise exception 'not allowed'; end if;
  if them = 'admin' and me <> 'owner' then raise exception 'not allowed'; end if;
  delete from chat_members where chat_id = c and user_id = u;
  if ban then
    insert into chat_bans (chat_id, user_id, banned_by) values (c, u, auth.uid()) on conflict do nothing;
  end if;
end $$;

create or replace function public.unban_member(c uuid, u uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can(c, 'ban') then raise exception 'not allowed'; end if;
  delete from chat_bans where chat_id = c and user_id = u;
end $$;

create or replace function public.add_group_member(chat uuid, member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from chats where id = chat and is_group) or not public.can(chat, 'add') then
    raise exception 'not allowed';
  end if;
  -- adding someone back lifts their ban only if the adder may ban
  if exists (select 1 from chat_bans b where b.chat_id = chat and b.user_id = member) then
    if not public.can(chat, 'ban') then raise exception 'banned'; end if;
    delete from chat_bans b where b.chat_id = chat and b.user_id = member;
  end if;
  insert into chat_members (chat_id, user_id) values (chat, member) on conflict do nothing;
end $$;

create or replace function public.set_pinned_message(c uuid, m uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.can(c, 'pin') then raise exception 'not allowed'; end if;
  if m is not null and not exists (select 1 from messages where id = m and chat_id = c) then raise exception 'bad message'; end if;
  update chats set pinned_message_id = m where id = c;
end $$;

-- Group photo for direct chats is not a thing; keep set via update_group.
create or replace function public.set_group_username(c uuid, uname text) returns void
language plpgsql security definer set search_path = public as $$
declare me text;
begin
  select role into me from chat_members where chat_id = c and user_id = auth.uid();
  if me is distinct from 'owner' then raise exception 'not allowed'; end if;
  update chats set username = nullif(lower(trim(both '@' from trim(uname))), '') where id = c and is_group;
end $$;

create or replace function public.delete_group(c uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from chat_members where chat_id = c and user_id = auth.uid() and role = 'owner') then
    raise exception 'not allowed';
  end if;
  delete from chats where id = c and is_group;
end $$;

-- When the owner leaves, the longest-serving admin (else member) takes over.
create or replace function public.pass_ownership() returns trigger
language plpgsql security definer set search_path = public as $$
declare next uuid;
begin
  if old.role = 'owner' then
    select user_id into next from chat_members where chat_id = old.chat_id
     order by (role = 'admin') desc, joined_at limit 1;
    if next is not null then
      update chat_members set role = 'owner', rights = null where chat_id = old.chat_id and user_id = next;
    end if;
  end if;
  return old;
end $$;
drop trigger if exists pass_ownership on public.chat_members;
create trigger pass_ownership after delete on public.chat_members for each row execute function public.pass_ownership();

-- New groups: the creator is the owner.
create or replace function public.create_group(title text, members uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null or coalesce(trim(title), '') = '' then raise exception 'invalid group'; end if;
  insert into chats (is_group, title, created_by) values (true, trim(title), auth.uid()) returning id into cid;
  insert into chat_members (chat_id, user_id, role) values (cid, auth.uid(), 'owner');
  insert into chat_members (chat_id, user_id)
    select cid, m from unnest(members) m where m <> auth.uid() and exists (select 1 from profiles where id = m)
    on conflict do nothing;
  return cid;
end $$;

-- ── Invite links ────────────────────────────────────────────────────────────
create or replace function public.create_invite(c uuid, hours integer default null, max_uses integer default null) returns text
language plpgsql security definer set search_path = public as $$
declare code text;
begin
  if not exists (select 1 from chats where id = c and is_group) or not public.can(c, 'invite') then
    raise exception 'not allowed';
  end if;
  code := substr(replace(gen_random_uuid()::text, '-', ''), 1, 16);
  insert into chat_invites (code, chat_id, created_by, expires_at, usage_limit)
  values (code, c, auth.uid(), case when hours is null then null else now() + make_interval(hours => hours) end, max_uses);
  return code;
end $$;

create or replace function public.revoke_invite(k text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update chat_invites set revoked = true
   where code = k and public.can(chat_id, 'invite');
end $$;

-- What a link leads to (for the "join group" sheet). Works for non-members.
create or replace function public.invite_info(k text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'chat_id', c.id, 'title', c.title, 'avatar_path', c.avatar_path, 'description', c.description,
    'members', (select count(*) from chat_members m where m.chat_id = c.id),
    'member', exists (select 1 from chat_members m where m.chat_id = c.id and m.user_id = auth.uid()))
  from chats c
  where c.is_group and (
    c.id = (select i.chat_id from chat_invites i where i.code = k and not i.revoked
              and (i.expires_at is null or i.expires_at > now())
              and (i.usage_limit is null or i.uses < i.usage_limit))
    or c.username = lower(trim(both '@' from k)));
$$;

create or replace function public.join_by_invite(k text) returns uuid
language plpgsql security definer set search_path = public as $$
declare c uuid; inv text;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select i.chat_id, i.code into c, inv from chat_invites i where i.code = k and not i.revoked
     and (i.expires_at is null or i.expires_at > now())
     and (i.usage_limit is null or i.uses < i.usage_limit);
  if c is null then select id into c from chats where is_group and username = lower(trim(both '@' from k)); end if;
  if c is null then raise exception 'invalid link'; end if;
  if exists (select 1 from chat_bans where chat_id = c and user_id = auth.uid()) then raise exception 'banned'; end if;
  if exists (select 1 from chat_members where chat_id = c and user_id = auth.uid()) then return c; end if;
  insert into chat_members (chat_id, user_id) values (c, auth.uid());
  if inv is not null then update chat_invites set uses = uses + 1 where code = inv; end if;
  return c;
end $$;

revoke execute on function public.update_group, public.set_group_permissions, public.set_member_role,
  public.remove_member, public.unban_member, public.set_pinned_message, public.set_group_username,
  public.delete_group, public.create_invite, public.revoke_invite, public.invite_info, public.join_by_invite from anon;

-- ── Chat list carries the group details ────────────────────────────────────
create or replace function public.my_chats() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r order by r->>'last_message_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', c.id, 'is_group', c.is_group, 'is_saved', c.is_saved, 'title', c.title, 'avatar_path', c.avatar_path,
      'description', c.description, 'username', c.username, 'permissions', c.permissions,
      'pinned_message_id', c.pinned_message_id,
      'last_message_at', c.last_message_at, 'my_last_read_at', me.last_read_at,
      'pinned_at', me.pinned_at, 'muted', me.muted, 'archived', me.archived,
      'marked_unread', me.marked_unread, 'cleared_at', me.cleared_at,
      'members', (select jsonb_agg(jsonb_build_object(
                    'id', p.id, 'email', p.email, 'display_name', p.display_name,
                    'username', p.username, 'avatar_path', p.avatar_path,
                    'last_read_at', m.last_read_at, 'role', m.role, 'rights', m.rights)
                    order by (m.role = 'owner') desc, (m.role = 'admin') desc, m.joined_at)
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

-- Delete for everyone: the sender, or a group admin with the right to delete.
create or replace function public.delete_message(m uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update messages x set deleted_at = now(), body = '', file_path = null, file_name = null,
         file_size = null, mime_type = null, duration_ms = null, meta = null, cipher = null
  where x.id = m and (x.sender_id = auth.uid()
        or (public.can(x.chat_id, 'delete') and exists (select 1 from chats c where c.id = x.chat_id and c.is_group)));
end $$;
revoke execute on function public.delete_message from anon;

-- Hand out chat-key copies, replacing a member's copy made for an old key
-- (a plain upsert is refused: the old row belongs to someone else).
create or replace function public.put_chat_keys(rows jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare r jsonb;
begin
  for r in select * from jsonb_array_elements(rows) loop
    if not public.is_member((r->>'chat_id')::uuid) or not public.is_member_of((r->>'chat_id')::uuid, (r->>'user_id')::uuid) then
      raise exception 'not allowed';
    end if;
    insert into chat_keys (chat_id, user_id, key_id, wrapped, wrapped_by, for_pub)
    values ((r->>'chat_id')::uuid, (r->>'user_id')::uuid, (r->>'key_id')::int, r->>'wrapped', auth.uid(), r->>'for_pub')
    on conflict (chat_id, user_id, key_id) do update
      set wrapped = excluded.wrapped, wrapped_by = excluded.wrapped_by, for_pub = excluded.for_pub, created_at = now();
  end loop;
end $$;
revoke execute on function public.put_chat_keys from anon;
