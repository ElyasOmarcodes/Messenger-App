-- Paigham v11: push notifications (FCM / APNs) and presence (online / last seen).
-- Run once in the Supabase SQL Editor after the v10 file. Then fill
-- push_config (see docs/PUSH_AND_TURN.md).

-- ── Push tokens: one row per phone ──────────────────────────────────────────
create table if not exists public.push_tokens (
  token      text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  platform   text not null check (platform in ('android', 'ios', 'web', 'other')),
  lang       text,
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
drop policy if exists push_tokens_own on public.push_tokens;
create policy push_tokens_own on public.push_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Where the database sends "something happened" (the push Edge Function).
-- No policies: only the database itself (security definer) reads it.
create table if not exists public.push_config (
  id     integer primary key default 1 check (id = 1),
  url    text not null,       -- https://<project>.supabase.co/functions/v1/push
  secret text not null        -- the same value as the function's PUSH_SECRET
);
alter table public.push_config enable row level security;

create extension if not exists pg_net with schema extensions;

-- New message or ringing call → tell the push function (it finds the
-- recipients, their phones and sends; it never sees message content: with
-- end-to-end encryption the row only holds ciphertext).
create or replace function public.push_notify() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare cfg record;
begin
  select * into cfg from push_config where id = 1;
  if cfg is null then return new; end if;
  perform net.http_post(
    url := cfg.url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', cfg.secret),
    body := jsonb_build_object('table', tg_table_name, 'record', to_jsonb(new))
  );
  return new;
exception when others then
  return new; -- a push problem must never block sending
end $$;

drop trigger if exists push_on_message on public.messages;
create trigger push_on_message after insert on public.messages
  for each row execute function public.push_notify();

drop trigger if exists push_on_call on public.calls;
create trigger push_on_call after insert on public.calls
  for each row when (new.status = 'ringing') execute function public.push_notify();

-- ── Presence: last seen ─────────────────────────────────────────────────────
alter table public.profiles add column if not exists last_seen timestamptz;

create or replace function public.touch_presence() returns void
language sql security definer set search_path = public as $$
  update profiles set last_seen = now() where id = auth.uid();
$$;
revoke execute on function public.touch_presence from anon;

-- my_chats as in v10, members also carry last_seen
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
                    'username', p.username, 'avatar_path', p.avatar_path, 'last_seen', p.last_seen,
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
