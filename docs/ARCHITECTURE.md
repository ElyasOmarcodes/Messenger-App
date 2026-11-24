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

## Calls behind mobile networks

Calls connect directly between phones using free STUN servers. On some mobile networks (carrier-grade NAT) a direct path is impossible and a TURN relay is needed. When we have our own server, install `coturn` on it and build with
`--dart-define=TURN_URL=turn:turn.example.af:3478 --dart-define=TURN_USER=... --dart-define=TURN_PASS=...`.

## Push notifications to a closed app

Notifications currently work while the app is open or in the background. Waking a fully closed app requires Firebase Cloud Messaging (Android) and APNs (iPhone). This needs a Firebase project owned by the Paigham team; once created, add `google-services.json` and a small Supabase Edge Function that sends a push when a message is inserted.
