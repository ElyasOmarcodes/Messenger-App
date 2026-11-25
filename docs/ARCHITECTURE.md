# Architecture and roadmap

## Why Supabase

| Need | Supabase | Firebase | Own server now |
|---|---|---|---|
| Email accounts with codes | ✓ built in | ✓ | build it ourselves |
| Realtime messages | ✓ | ✓ | build it |
| File storage | ✓ | ✓ | build it |
| Windows + Linux apps | ✓ (pure Dart SDK) | weak desktop support | ✓ |
| Open source, self-hostable later | ✓ | ✗ (locked in) | ✓ |
| Free to start | ✓ | ✓ | ✗ (server cost) |

Supabase is the only option that is free today **and** can move to our own server later without rewriting the app.

## App code (`app/lib/`)

```
main.dart                 Supabase init, theme, language, auth gate
config.dart               Server URL/key (from --dart-define)
brand/                    Name, colours, theme, logo
l10n/                     Pashto / Dari / English strings, Afghan calendar
models/models.dart        Profile, Chat, Message
services/messenger.dart   Auth, chats, realtime, sending text/files, read receipts
screens/                  Account screens, chats, chat, new chat, calls, settings
widgets/                  Avatar, message bubble (text, photo, file)
```

## Database (`backend/supabase/migrations/`)

- `profiles` — one row per account (created by a trigger on sign-up)
- `chats`, `chat_members` (with `last_read_at` for read receipts), `messages`
- Storage bucket `attachments` (private), path `<chat_id>/<time>-<file name>`
- RPCs: `find_user` (exact email/@username only — never lists users), `start_direct_chat`, `create_group`, `add_group_member`, `my_chats` (whole chat list in one request)
- Row Level Security on every table and on storage: only chat members can read a chat's messages and files. Verified: a third account sees nothing.

## Roadmap

1. **Now:** email accounts, 1:1 and group chats, photos and files, read receipts, all platforms.
2. **Done since:** voice notes, reply, edit, delete, reactions, pins, albums, location, contacts, stories, profile and group photos, calls.
3. **Next:** push notifications (FCM / APNs), online status, channels.
4. **Then:** own TURN server for calls, end-to-end encryption.
5. **Own server:** self-host Supabase (Docker) in our data centre, custom SMTP, then Play Store / App Store.

## Database updates

Run each file in `backend/supabase/migrations/` once, in order, in the Supabase SQL Editor:

1. `20261124000000_paigham_core.sql`: accounts, chats, messages, files
2. `20261125000000_paigham_v3.sql`: profile photos, replies, delete, voice notes, calls, sign-in check (`email_status`)
3. `20261126000000_paigham_v5.sql`: message edit, reactions, pinned messages, albums, location and contact messages, group photos, and 24-hour stories (`stories`, `story_views`, `story_feed`, `story_viewers`, private `stories` bucket)
4. `20261127000000_paigham_v6.sql`: Saved Messages (`saved_chat`) and per-person chat options on `chat_members` (pinned, muted, archived, marked unread, cleared history)
5. `20261128000000_paigham_v7.sql`: hearts on stories (`story_views.liked`, `like_story`, likes in `story_feed` / `story_viewers`)
6. `20261129000000_paigham_v8.sql`: end-to-end encryption (`user_keys`, `key_backups`, `chat_keys`, `chat_key_state`, `messages.cipher` / `key_id`, `edit_message_e2e`). Until it is run, the app keeps working without encryption.
7. `20261130000000_paigham_v9.sql`: nothing readable after a server break-in: sealed stories (`stories.cipher`, `story_keys`, `story_audience`), sealed reactions, `seal_old_message` for messages from before v8, and deleting one's own old attachment files.

## End-to-end encryption

- Each user has an X25519 key pair; the private key stays on the phone
  (Keystore / Keychain). Its backup is locked with the user's PIN through
  Argon2id (64 MiB, 2 passes; 19 MiB on the web) and AES-256-GCM; the PIN
  never leaves the phone.
- Each chat has random AES-256 keys, numbered. Every member gets a copy
  locked with X25519 + HKDF-SHA256 between the sender and that member. A new
  key is made when someone leaves; members who join or set up keys later get
  a copy from the next member who opens the chat.
- Message content (text, captions, metadata, file names, types, durations,
  file keys) is sealed with AES-256-GCM; chat, message id, sender and key
  number are bound in, so the server cannot move or re-attribute it.
- Each file has its own random AES-256-GCM key; storage holds ciphertext.
- Stories are sealed the same way (a fresh key per story, a copy locked for
  each person who may see it); reactions are sealed with the chat key.
- Messages from before encryption are sealed by their sender's phone, and
  their plain files are replaced by encrypted copies and deleted.
- The PIN must be strong (8+ characters with letters and digits, or 12+),
  so the locked backups cannot be guessed offline after a break-in.
- Keys are pinned on first sight (like Signal): if the server shows a
  different key for someone, nothing is locked for it, old messages still
  open with the pinned key, and the chat shows a warning until the person
  is checked (safety number) and accepted. A one-to-one chat never hands its
  key to a third member.

What a server break-in still reveals: who talks to whom and when, message
kinds and sizes, profile names, usernames, emails and photos, and group
names and photos. A server that is not only read but taken over could add a
new member to a group (members see it in the member list). There is no
forward secrecy yet (no ratchet): a stolen phone key opens past messages of
its chats.
- Safety numbers (profile page) let two people check that no one is in
  between.

## Offline sending (outbox)

Every outgoing message (text, photo, album, voice, file, location, contact,
forward) first goes into an outbox saved on the phone, and shows at once with
a clock. The outbox is sent in order; with no internet it waits and retries
every few seconds, when the app comes back to the front and when the realtime
connection returns, and it survives an app restart. The message id is made on
the phone, so a retry whose first answer was lost never creates a copy
(duplicate insert = already sent; an existing file in storage = already
uploaded). Only a real refusal from the server turns the message red (tap to
try again).

## Calls behind mobile networks

Calls connect directly between phones using free STUN servers. On some mobile networks (carrier-grade NAT) a direct path is impossible and a TURN relay is needed. When we have our own server, install `coturn` on it and build with
`--dart-define=TURN_URL=turn:turn.example.af:3478 --dart-define=TURN_USER=... --dart-define=TURN_PASS=...`.

## Push notifications to a closed app

Notifications currently work while the app is open or in the background. Waking a fully closed app requires Firebase Cloud Messaging (Android) and APNs (iPhone). This needs a Firebase project owned by the Paigham team; once created, add `google-services.json` and a small Supabase Edge Function that sends a push when a message is inserted.
