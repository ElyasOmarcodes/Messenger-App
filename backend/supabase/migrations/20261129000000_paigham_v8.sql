-- Paigham v8: end-to-end encryption.
--
-- The server only ever sees:
--   * each user's PUBLIC key (user_keys),
--   * each user's private key LOCKED with their own PIN (key_backups;
--     the PIN never leaves the phone, so the server cannot open it),
--   * every chat key LOCKED separately for each member (chat_keys),
--   * messages as ciphertext (messages.cipher) and files as ciphertext.
-- Who talks to whom, when, message kind and file size stay visible (like
-- WhatsApp); the content does not.

create table if not exists public.user_keys (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  public_key text not null check (char_length(public_key) between 40 and 64),
  updated_at timestamptz not null default now()
);
alter table public.user_keys enable row level security;
drop policy if exists user_keys_read on public.user_keys;
create policy user_keys_read on public.user_keys for select to authenticated using (true);
drop policy if exists user_keys_insert on public.user_keys;
create policy user_keys_insert on public.user_keys for insert to authenticated with check (user_id = auth.uid());
drop policy if exists user_keys_update on public.user_keys;
create policy user_keys_update on public.user_keys for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.key_backups (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);
alter table public.key_backups enable row level security;
drop policy if exists key_backups_own on public.key_backups;
create policy key_backups_own on public.key_backups for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Is [u] a member of chat [c]? (any user, not only the caller)
create or replace function public.is_member_of(c uuid, u uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_members where chat_id = c and user_id = u);
$$;
revoke execute on function public.is_member_of from anon;

create table if not exists public.chat_keys (
  chat_id    uuid not null references public.chats(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  key_id     integer not null check (key_id > 0),
  wrapped    text not null check (char_length(wrapped) < 200),
  wrapped_by uuid not null references public.profiles(id) on delete cascade,
  for_pub    text not null,  -- the member's public key this copy was locked for
  created_at timestamptz not null default now(),
  primary key (chat_id, user_id, key_id)
);
alter table public.chat_keys enable row level security;
drop policy if exists chat_keys_read on public.chat_keys;
create policy chat_keys_read on public.chat_keys for select to authenticated using (user_id = auth.uid());
drop policy if exists chat_keys_insert on public.chat_keys;
create policy chat_keys_insert on public.chat_keys for insert to authenticated
  with check (wrapped_by = auth.uid() and public.is_member(chat_id) and public.is_member_of(chat_id, user_id));

-- a member's copy made for an old public key (they reset their key) is replaced
drop policy if exists chat_keys_update on public.chat_keys;
create policy chat_keys_update on public.chat_keys for update to authenticated
  using (public.is_member(chat_id))
  with check (wrapped_by = auth.uid() and public.is_member(chat_id) and public.is_member_of(chat_id, user_id));

alter table public.messages add column if not exists cipher text check (char_length(cipher) <= 20000);
alter table public.messages add column if not exists key_id integer;

-- What the caller's phone must do for a chat's key:
--   latest  = newest key number (null: no key yet),
--   keys    = every member's public key (for a new chat key),
--   missing = members with a public key who have no copy of the newest key
--             (or whose copy was made for an older public key),
--   stale   = someone who left still holds the newest key (make a new one).
create or replace function public.chat_key_state(c uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  latest integer;
begin
  if not public.is_member(c) then raise exception 'not a member'; end if;
  select max(key_id) into latest from chat_keys where chat_id = c;
  return jsonb_build_object(
    'latest', latest,
    'keys', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'public_key', k.public_key))
      from chat_members m join user_keys k on k.user_id = m.user_id where m.chat_id = c
    ), '[]'::jsonb),
    'missing', coalesce((
      select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'public_key', k.public_key))
      from chat_members m join user_keys k on k.user_id = m.user_id
      where m.chat_id = c and (latest is null or not exists (
        select 1 from chat_keys ck where ck.chat_id = c and ck.user_id = m.user_id
          and ck.key_id = latest and ck.for_pub = k.public_key))
    ), '[]'::jsonb),
    'stale', latest is not null and exists (
      select 1 from chat_keys ck where ck.chat_id = c and ck.key_id = latest
        and not exists (select 1 from chat_members m where m.chat_id = c and m.user_id = ck.user_id))
  );
end $$;
revoke execute on function public.chat_key_state from anon;

-- Editing an encrypted message replaces its ciphertext.
create or replace function public.edit_message_e2e(m uuid, new_cipher text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if char_length(coalesce(new_cipher, '')) > 20000 then raise exception 'too long'; end if;
  update messages set cipher = new_cipher, edited_at = now()
  where id = m and sender_id = auth.uid() and deleted_at is null and cipher is not null;
end $$;
revoke execute on function public.edit_message_e2e from anon;

-- Delete for everyone also wipes the ciphertext.
create or replace function public.delete_message(m uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update messages set deleted_at = now(), body = '', file_path = null, file_name = null,
         file_size = null, mime_type = null, duration_ms = null, meta = null, cipher = null
  where id = m and sender_id = auth.uid();
end $$;
revoke execute on function public.delete_message from anon;
