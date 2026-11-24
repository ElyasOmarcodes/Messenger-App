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
2. **Next:** push notifications (FCM / APNs), voice notes, message delete/edit/reply, profile photos, online status.
3. **Then:** voice/video calls (WebRTC + own TURN server), end-to-end encryption, channels.
4. **Own server:** self-host Supabase (Docker) in our data centre, custom SMTP, then Play Store / App Store.
