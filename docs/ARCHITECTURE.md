# Architecture and roadmap

## Code layout (`app/lib/`)

```
main.dart                 App entry: theme, language, onboarding vs home
brand/brand.dart          Name, colours, theme (single place to rebrand)
brand/logo.dart           Logo + star wallpaper painters
l10n/strings.dart         Pashto / Dari / English strings, digit conversion
l10n/afghan_date.dart     Solar Hijri calendar, Pashto & Dari month names
models/models.dart        Profile, Chat, Message, IDs
services/relay.dart       Transport (ntfy.sh today, our server later)
services/messenger.dart   App state: chats, sending, receipts, bot, storage
services/apis.dart        Weather, prayer times, rates, Quran clients
screens/                  Onboarding, home, chat list, chat, services, calls, settings
widgets/                  Avatar, message bubble
```

State lives in one `AppController` (a `ChangeNotifier`) exposed through `AppScope`. Data is stored on the device with `shared_preferences` (localStorage on web).

## Wire protocol v1

Messages are JSON strings published to ntfy topics:

| Topic | Who listens |
|---|---|
| `pgm1-u-<userId>` | The user's inbox (direct messages, receipts) |
| `pgm1-g-<groupId>` | Every member of a group |
| `pgm1-g-lobby` | Everyone (public lobby) |

```json
{"v":1,"t":"m","id":"<msgId>","f":"<senderId>","n":"<senderName>","x":"text","ts":1795498328000,"g":"<groupId?>","gn":"<groupName?>"}
{"v":1,"t":"a","f":"<senderId>","ids":["<msgId>"],"s":"d|r"}      // delivered / read receipt
{"v":1,"t":"j","id":"<id>","f":"<senderId>","n":"<name>","g":"<groupId>"}  // joined group
```

The client keeps the last event time and reconnects with `since=<time>`, de-duplicating by message id, so nothing is lost or shown twice after a reconnect.

## Known limits of the prototype

- **No end-to-end encryption yet.** Topic names are random and hard to guess, but anyone who knows an ID can read that inbox. Do not send sensitive information.
- No phone-number verification; the phone field is only stored on the device.
- One device per account; history lives on the device.
- ntfy.sh's free tier has daily request limits per IP address.
- Calls, voice notes, photos and push notifications are not built yet.

## Roadmap

**Phase 1 (this version):** brand, three languages, text chat, groups, lobby, bot, services, builds for every platform.

**Phase 2: own server**
- Self-host ntfy (or a custom Dart/Go server) on our own machine; switch the address in Settings.
- Sign-in with SMS (Afghan carriers: Roshan, AWCC, Etisalat, MTN/Salaam).
- End-to-end encryption (Signal protocol / X25519 + AES-GCM).
- Push notifications (UnifiedPush via ntfy on Android, APNs on iPhone).

**Phase 3: media and calls**
- Photos, files and voice notes with compression tuned for slow networks.
- Voice and video calls (WebRTC with our own TURN server).
- Channels anyone can create, multi-device sync, backups.

**Phase 4: stores**
- Google Play, Apple App Store, Microsoft Store; a website for direct APK download.
