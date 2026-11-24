-- Paigham core schema: profiles, chats, members, messages, file attachments.
-- Every table uses Row Level Security: users only ever see chats they belong to.

create extension if not exists pgcrypto;

-- ── Profiles ────────────────────────────────────────────────────────────────
create table public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text not null unique,
  display_name text not null default '',
  username     text unique check (username ~ '^[a-z0-9_]{3,24}$'),
  about        text not null default '',
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, display_name)
  values (new.id, lower(new.email),
          coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── Chats ───────────────────────────────────────────────────────────────────
create table public.chats (
  id              uuid primary key default gen_random_uuid(),
  is_group        boolean not null default false,
  title           text,
  created_by      uuid references public.profiles(id) on delete set null,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

create table public.chat_members (
  chat_id      uuid not null references public.chats(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  role         text not null default 'member' check (role in ('admin', 'member')),
  joined_at    timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  primary key (chat_id, user_id)
);
create index on public.chat_members (user_id);

create table public.messages (
  id         uuid primary key default gen_random_uuid(),
  chat_id    uuid not null references public.chats(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  kind       text not null default 'text' check (kind in ('text', 'image', 'file')),
  body       text not null default '' check (char_length(body) <= 4000),
  file_path  text,
  file_name  text,
  file_size  bigint,
  mime_type  text,
  created_at timestamptz not null default now()
);
create index on public.messages (chat_id, created_at desc);

-- Membership check used by every policy (security definer avoids RLS recursion).
create or replace function public.is_member(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_members where chat_id = c and user_id = auth.uid());
$$;

create or replace function public.touch_chat() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update chats set last_message_at = new.created_at where id = new.chat_id;
  update chat_members set last_read_at = new.created_at
    where chat_id = new.chat_id and user_id = new.sender_id;
  return new;
end $$;
create trigger on_message_insert after insert on public.messages
  for each row execute function public.touch_chat();

-- ── Row Level Security ──────────────────────────────────────────────────────
alter table public.profiles     enable row level security;
alter table public.chats        enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages     enable row level security;

-- Profiles: yourself, and people you share a chat with.
create policy profiles_select on public.profiles for select to authenticated using (
  id = auth.uid() or exists (
    select 1 from chat_members a join chat_members b on a.chat_id = b.chat_id
    where a.user_id = auth.uid() and b.user_id = profiles.id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

create policy chats_select on public.chats for select to authenticated using (public.is_member(id));
create policy chats_update on public.chats for update to authenticated using (public.is_member(id));

create policy members_select on public.chat_members for select to authenticated using (public.is_member(chat_id));
create policy members_update_self on public.chat_members for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy members_leave on public.chat_members for delete to authenticated using (user_id = auth.uid());

create policy messages_select on public.messages for select to authenticated using (public.is_member(chat_id));
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_member(chat_id));
create policy messages_delete_own on public.messages for delete to authenticated using (sender_id = auth.uid());

-- ── RPCs (the only way to create chats or look people up) ──────────────────
-- Exact match on email or username; never lists all users.
create or replace function public.find_user(q text)
returns table (id uuid, email text, display_name text, username text)
language sql stable security definer set search_path = public as $$
  select p.id, p.email, p.display_name, p.username from profiles p
  where (p.email = lower(trim(q)) or p.username = lower(trim(both '@' from trim(q))))
    and p.id <> auth.uid()
  limit 1;
$$;

create or replace function public.start_direct_chat(other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null or other = auth.uid() then raise exception 'invalid user'; end if;
  select c.id into cid from chats c
    join chat_members a on a.chat_id = c.id and a.user_id = auth.uid()
    join chat_members b on b.chat_id = c.id and b.user_id = other
    where not c.is_group limit 1;
  if cid is not null then return cid; end if;
  insert into chats (is_group, created_by) values (false, auth.uid()) returning id into cid;
  insert into chat_members (chat_id, user_id) values (cid, auth.uid()), (cid, other);
  return cid;
end $$;

create or replace function public.create_group(title text, members uuid[]) returns uuid
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  if auth.uid() is null or coalesce(trim(title), '') = '' then raise exception 'invalid group'; end if;
  insert into chats (is_group, title, created_by) values (true, trim(title), auth.uid()) returning id into cid;
  insert into chat_members (chat_id, user_id, role) values (cid, auth.uid(), 'admin');
  insert into chat_members (chat_id, user_id)
    select cid, m from unnest(members) m where m <> auth.uid() and exists (select 1 from profiles where id = m)
    on conflict do nothing;
  return cid;
end $$;

create or replace function public.add_group_member(chat uuid, member uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from chat_members cm join chats c on c.id = cm.chat_id
                 where cm.chat_id = chat and cm.user_id = auth.uid() and c.is_group) then
    raise exception 'not allowed';
  end if;
  insert into chat_members (chat_id, user_id) values (chat, member) on conflict do nothing;
end $$;

revoke execute on function public.find_user, public.start_direct_chat, public.create_group, public.add_group_member from anon;

-- ── Realtime ────────────────────────────────────────────────────────────────
alter publication supabase_realtime add table public.messages, public.chat_members, public.chats;

-- ── File storage: private bucket, path "<chat_id>/<uuid>-<file name>" ──────
insert into storage.buckets (id, name, public, file_size_limit)
values ('attachments', 'attachments', false, 52428800)  -- 50 MB per file
on conflict (id) do nothing;

create policy attachments_read on storage.objects for select to authenticated
  using (bucket_id = 'attachments' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy attachments_write on storage.objects for insert to authenticated
  with check (bucket_id = 'attachments' and public.is_member(((storage.foldername(name))[1])::uuid));

-- ── Chat list in one round trip (members, last message, unread count) ─────
create or replace function public.my_chats() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r order by r->>'last_message_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', c.id, 'is_group', c.is_group, 'title', c.title,
      'last_message_at', c.last_message_at, 'my_last_read_at', me.last_read_at,
      'members', (select jsonb_agg(jsonb_build_object(
                    'id', p.id, 'email', p.email, 'display_name', p.display_name,
                    'username', p.username, 'last_read_at', m.last_read_at, 'role', m.role))
                  from chat_members m join profiles p on p.id = m.user_id where m.chat_id = c.id),
      'last_message', (select to_jsonb(x) from (select * from messages where chat_id = c.id
                       order by created_at desc limit 1) x),
      'unread', (select count(*) from messages where chat_id = c.id
                 and created_at > me.last_read_at and sender_id <> auth.uid())
    ) as r
    from chats c join chat_members me on me.chat_id = c.id and me.user_id = auth.uid()
  ) t;
$$;
revoke execute on function public.my_chats from anon;
