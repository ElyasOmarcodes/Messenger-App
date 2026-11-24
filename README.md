<p align="center"><img src="app/assets/brand/logo.png" width="110" alt="Paigham logo"></p>

<h1 align="center">پیغام · Paigham</h1>
<p align="center"><b>د افغانانو خپل پیغام رسان</b> — The Afghan messenger</p>
<p align="center">Android · iPhone · Windows · macOS · Linux · Web — له یوه کوډ څخه / one codebase</p>

---

<div dir="rtl">

## پیغام څه کوي؟

- **په ایمیل حساب جوړول:** ایمیل او پټنوم، بیا ایمیل ته راغلی ۶ عددي کوډ. ننوتل، وتل، او د هېر شوي پټنوم بدلول.
- **خلک موندل** د ایمیل یا @کارن‌نوم له لارې، او ورسره چټ پیل کول.
- **پیغامونه، انځورونه او فایلونه** (PDF، Word، Excel، ZIP، غږ، ویډیو… تر ۵۰ MB).
- **ډلې** جوړول او غړي ورزیاتول.
- **غږیز پیغامونه، ځواب (reply)، د ټولو لپاره ړنګول، د پروفایل انځور.**
- **کیسې (Stories):** انځور یا رنګین متن د ۲۴ ساعتو لپاره؛ کتونکي، ځواب، ړنګول.
- **د پیغام سمول، غبرګونونه (reactions)، پورته نښلول (pin)، بل چا ته لېږل (forward).**
- **ګڼ انځورونه (album)، ځای (location)، اړیکه (contact)**، او بشپړه د ایموجي تخته.
- د ټلګرام په څېر: سره نښتي پیغامونه، د ځواب لپاره کش کول، د غږ تڼۍ (نیول، کش کول، قفل)، د ړنګولو د دوړو انیمیشن.
- **غږیز او ویډیويي زنګونه** (WebRTC).
- د ټلګرام په څېر ډیزاین، **شپې بڼه (night mode)**، او لاندې تیرېدونکې مېنو.
- **ژر رسېدل** (realtime)، او ✓ لېږل شوی / ✓✓ لوستل شوی نښې.
- په هره وسیله ننوځئ، ټول پیغامونه مو هلته وي.
- پښتو، دری او انګلیسي؛ روښانه او تیاره بڼه؛ لمریز کلیز.
- امنیت: هر څوک یوازې خپل چټونه او فایلونه لیدلی شي (په سرور کې Row Level Security).

## سرور: Supabase (اوس وړیا، وروسته خپل سرور)

۱. په [supabase.com](https://supabase.com) کې وړیا حساب او نوې پروژه جوړه کړئ.
۲. د `backend/supabase/migrations/` فایل په **SQL Editor** کې ورکړئ او Run یې کړئ.
۳. په **Authentication → Email Templates** کې د `backend/supabase/templates/` متن ورکړئ (تر څو کوډ په ایمیل کې راشي).
۴. له **Project Settings → API** څخه `Project URL` او `anon/publishable key` واخلئ.
۵. په GitHub کې: **Settings → Secrets and variables → Actions → Variables** کې دا دوه ورزیات کړئ: `SUPABASE_URL` او `SUPABASE_ANON_KEY`. بیا هر نوی build په همدې سرور وصلېږي.

</div>

## Screenshots

**v0.5 — stories, albums, emoji, message menu:**

| Home + stories | Scrolled (header folds) | Joined bubbles | Emoji panel |
|---|---|---|---|
| <img src="docs/screenshots/v5_01_home_stories.png" width="190"> | <img src="docs/screenshots/v5_02_home_scrolled.png" width="190"> | <img src="docs/screenshots/v5_03_chat_grouped.png" width="190"> | <img src="docs/screenshots/v5_04_emoji.png" width="190"> |

| Attach | Album + location | Message menu | Hold to record |
|---|---|---|---|
| <img src="docs/screenshots/v5_05_attach.png" width="190"> | <img src="docs/screenshots/v5_06_album_location.png" width="190"> | <img src="docs/screenshots/v5_07_message_menu.png" width="190"> | <img src="docs/screenshots/v5_08_voice_hold.png" width="190"> |

| Story | New text story | Home (night, Dari) | Chat (night) |
|---|---|---|---|
| <img src="docs/screenshots/v5_09_story.png" width="190"> | <img src="docs/screenshots/v5_10_story_composer.png" width="190"> | <img src="docs/screenshots/v5_11_home_dark.png" width="190"> | <img src="docs/screenshots/v5_12_chat_dark.png" width="190"> |

**Earlier versions:**

| Welcome | Email | New account | Email code |
|---|---|---|---|
| <img src="docs/screenshots/01_welcome.png" width="190"> | <img src="docs/screenshots/02_email.png" width="190"> | <img src="docs/screenshots/03_your_info.png" width="190"> | <img src="docs/screenshots/04_code.png" width="190"> |

| Chats (light) | Chats (night) | Chat (night) | Chat (light) |
|---|---|---|---|
| <img src="docs/screenshots/11_chats_light.png" width="190"> | <img src="docs/screenshots/07_chats_dark.png" width="190"> | <img src="docs/screenshots/08_chat_dark.png" width="190"> | <img src="docs/screenshots/09_chat_light.png" width="190"> |

| Profile | My profile (night) | Settings | Contacts & calls |
|---|---|---|---|
| <img src="docs/screenshots/10_user_profile.png" width="190"> | <img src="docs/screenshots/05_my_profile_dark.png" width="190"> | <img src="docs/screenshots/12_settings.png" width="190"> | <img src="docs/screenshots/13_contacts.png" width="190"> |

| Voice note & reply | Deleted message | Incoming call | Video call |
|---|---|---|---|
| <img src="docs/screenshots/v3_14_voice_and_reply.png" width="190"> | <img src="docs/screenshots/v3_16_deleted_seen_by_other.png" width="190"> | <img src="docs/screenshots/v3_18_incoming_call.png" width="190"> | <img src="docs/screenshots/v3_20_in_call_maryam.png" width="190"> |

**Desktop / web (night mode):**

<img src="docs/screenshots/15_desktop_dark.png" width="820">

## Architecture

| Part | Technology |
|---|---|
| App (all platforms) | Flutter / Dart — `app/` |
| Native hosts | Kotlin (Android), Swift (iOS/macOS), C++ (Windows/Linux) |
| Accounts | Supabase Auth: email + password, 6-digit email code, password reset |
| Database | Postgres with Row Level Security — `backend/supabase/migrations/` |
| Realtime | Supabase Realtime (new messages, read receipts) |
| Files | Supabase Storage, private bucket, 50 MB per file, short-lived signed links |
| Builds | GitHub Actions — `.github/workflows/build.yml` → Releases |

Supabase is open source. When we buy our own server we self-host the same stack and only change `SUPABASE_URL`.

**Free tier (enough for testing and early users):** 50,000 monthly users, 500 MB database, 1 GB files. Its built-in email sender is limited to a few emails per hour, so before launch connect a free SMTP provider (e.g. Brevo or Resend) under *Authentication → SMTP*.

## Run locally

```bash
# backend (needs Docker)
cd backend && npm install && npm start        # local Supabase; test emails at http://127.0.0.1:54324

# app
cd app
flutter run -d chrome \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<anon key printed by npm start>
flutter test
```

## Builds

Every push builds Android (APK/AAB), iOS (unsigned IPA), Windows, macOS, Linux and Web and publishes them as a GitHub Release. Optional secrets for a fixed Android signature: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and [docs/BRAND.md](docs/BRAND.md).
