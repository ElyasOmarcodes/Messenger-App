-- Paigham v0.3: profile photos, replies, delete, voice notes, calls.
-- Run this once in the Supabase SQL Editor after the first migration.

-- ── Profile photos ──────────────────────────────────────────────────────────
alter table public.profiles add column if not exists avatar_path text;

insert into storage.buckets (id, name, public, file_size_limit)
values ('avatars', 'avatars', true, 5242880)  -- 5 MB, public read
on conflict (id) do nothing;

create policy avatars_read on storage.objects for select
  using (bucket_id = 'avatars');
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- ── Messages: replies, delete for everyone, voice notes ────────────────────
alter table public.messages add column if not exists reply_to uuid references public.messages(id) on delete set null;
alter table public.messages add column if not exists deleted_at timestamptz;
alter table public.messages add column if not exists duration_ms integer;
alter table public.messages drop constraint if exists messages_kind_check;
alter table public.messages add constraint messages_kind_check check (kind in ('text', 'image', 'file', 'voice'));

-- Senders may only "delete" (blank out) their own messages.
create or replace function public.delete_message(m uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update messages set deleted_at = now(), body = '', file_path = null, file_name = null,
         file_size = null, mime_type = null, duration_ms = null
  where id = m and sender_id = auth.uid();
end $$;
revoke execute on function public.delete_message from anon;

-- ── Calls (signalling through the database, members only) ──────────────────
create table if not exists public.calls (
  id          uuid primary key default gen_random_uuid(),
  chat_id     uuid not null references public.chats(id) on delete cascade,
  caller_id   uuid not null references public.profiles(id) on delete cascade,
  callee_id   uuid not null references public.profiles(id) on delete cascade,
  video       boolean not null default false,
  status      text not null default 'ringing' check (status in ('ringing', 'accepted', 'declined', 'ended', 'missed')),
  created_at  timestamptz not null default now(),
  answered_at timestamptz,
  ended_at    timestamptz
);
create index if not exists calls_callee on public.calls (callee_id, created_at desc);
create index if not exists calls_caller on public.calls (caller_id, created_at desc);

create table if not exists public.call_signals (
  id         bigserial primary key,
  call_id    uuid not null references public.calls(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  kind       text not null check (kind in ('offer', 'answer', 'ice')),
  payload    jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists call_signals_call on public.call_signals (call_id, id);

alter table public.calls        enable row level security;
alter table public.call_signals enable row level security;

create policy calls_select on public.calls for select to authenticated
  using (auth.uid() in (caller_id, callee_id));
create policy calls_insert on public.calls for insert to authenticated
  with check (caller_id = auth.uid() and public.is_member(chat_id)
              and exists (select 1 from chat_members where chat_id = calls.chat_id and user_id = callee_id));
create policy calls_update on public.calls for update to authenticated
  using (auth.uid() in (caller_id, callee_id));

create policy signals_select on public.call_signals for select to authenticated
  using (exists (select 1 from calls c where c.id = call_id and auth.uid() in (c.caller_id, c.callee_id)));
create policy signals_insert on public.call_signals for insert to authenticated
  with check (sender_id = auth.uid()
              and exists (select 1 from calls c where c.id = call_id and auth.uid() in (c.caller_id, c.callee_id)));

alter publication supabase_realtime add table public.calls, public.call_signals, public.profiles;
alter table public.messages replica identity full;

-- ── Lookups now include the profile photo ──────────────────────────────────
drop function if exists public.find_user(text);
create or replace function public.find_user(q text)
returns table (id uuid, email text, display_name text, username text, avatar_path text)
language sql stable security definer set search_path = public as $$
  select p.id, p.email, p.display_name, p.username, p.avatar_path from profiles p
  where (p.email = lower(trim(q)) or p.username = lower(trim(both '@' from trim(q))))
    and p.id <> auth.uid()
  limit 1;
$$;
revoke execute on function public.find_user from anon;

create or replace function public.my_chats() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(r order by r->>'last_message_at' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', c.id, 'is_group', c.is_group, 'title', c.title,
      'last_message_at', c.last_message_at, 'my_last_read_at', me.last_read_at,
      'members', (select jsonb_agg(jsonb_build_object(
                    'id', p.id, 'email', p.email, 'display_name', p.display_name,
                    'username', p.username, 'avatar_path', p.avatar_path,
                    'last_read_at', m.last_read_at, 'role', m.role))
                  from chat_members m join profiles p on p.id = m.user_id where m.chat_id = c.id),
      'last_message', (select to_jsonb(x) from (select * from messages where chat_id = c.id
                       order by created_at desc limit 1) x),
      'unread', (select count(*) from messages where chat_id = c.id
                 and created_at > me.last_read_at and sender_id <> auth.uid())
    ) as r
    from chats c join chat_members me on me.chat_id = c.id and me.user_id = auth.uid()
  ) t;
$$;

-- Call history for the Calls tab.
create or replace function public.my_calls() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb) from (
    select c.*, p.display_name as peer_name, p.email as peer_email, p.avatar_path as peer_avatar,
           (c.caller_id = auth.uid()) as outgoing
    from calls c
    join profiles p on p.id = case when c.caller_id = auth.uid() then c.callee_id else c.caller_id end
    where auth.uid() in (c.caller_id, c.callee_id)
    order by c.created_at desc limit 100
  ) x;
$$;
revoke execute on function public.my_calls from anon;

-- ── Sign-in flow: is this email new, waiting for its code, or active? ──────
create or replace function public.email_status(e text) returns text
language sql stable security definer set search_path = public, auth as $$
  select coalesce(
    (select case when u.email_confirmed_at is null then 'unconfirmed' else 'active' end
       from auth.users u where lower(u.email) = lower(trim(e)) limit 1),
    'new');
$$;
grant execute on function public.email_status(text) to anon, authenticated;
