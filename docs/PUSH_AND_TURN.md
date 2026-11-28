# Push notifications (FCM / APNs) and the TURN server

Without push, a phone only hears about new messages and calls while the
app's live connection is open. Android and iOS close it soon after the app
goes to the background, so messages and calls are missed. Push fixes that.
Without TURN, many calls over mobile data (carrier NAT / CGNAT) never connect.

The app and the server code are ready. Each needs a one-time setup that
only the owner can do (accounts, secrets, a server).

## 1. Firebase (push for Android, and for iPhone through APNs)

1. https://console.firebase.google.com → Add project (e.g. "Paigham").
2. Add an **Android app**, package name `af.paigham.messenger`. From the
   downloaded `google-services.json` note: `project_id`,
   `project_number` (= sender id), `mobilesdk_app_id` (= Android app id),
   `current_key` (= API key). Send these four values to the developer: they
   go into the build as `--dart-define=FCM_PROJECT_ID=… FCM_SENDER_ID=…
   FCM_ANDROID_APP_ID=… FCM_API_KEY=…`. They are not secret.
3. iPhone (when an iOS build is made): add an **iOS app** (bundle id
   `af.paigham.messenger`), note its app id (`FCM_IOS_APP_ID`), and in
   Project settings → Cloud Messaging upload an **APNs key** (.p8) from the
   Apple Developer account.
4. Project settings → Service accounts → **Generate new private key**. This
   JSON is a secret: never send it in chat. It goes only into Supabase (step 2).

## 2. Supabase: database, function, secrets

1. Run `backend/supabase/migrations/20261202000000_paigham_v11.sql` in the SQL
   Editor (push tokens, the push trigger, presence).
2. Deploy the functions (Supabase CLI, logged in to the project):
   ```
   cd backend
   npx supabase functions deploy push --no-verify-jwt
   npx supabase functions deploy turn
   ```
3. Secrets:
   ```
   npx supabase secrets set PUSH_SECRET="$(openssl rand -hex 24)"
   npx supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
   ```
4. Tell the database where to send (SQL Editor; the same PUSH_SECRET):
   ```sql
   insert into push_config (id, url, secret)
   values (1, 'https://<project-ref>.supabase.co/functions/v1/push', '<PUSH_SECRET>')
   on conflict (id) do update set url = excluded.url, secret = excluded.secret;
   ```

What a push contains: only who wrote and in which chat (and for calls, who
calls). Messages are end-to-end encrypted, so the text is never in a push;
the phone shows "New message" and fetches the message when opened.

## 3. TURN server (coturn)

1. A small VPS with a public IP (1 vCPU / 1 GB is enough to start); open
   UDP+TCP 3478, TCP 5349 and UDP 49160–49999.
2. Copy `backend/turn/` to it, edit `turnserver.conf` (a long random
   `static-auth-secret` and the server's `external-ip`), then
   `docker compose up -d`. A domain with a Let's Encrypt certificate enables
   `turns:` (TLS on 5349), which also passes strict firewalls.
3. Supabase secrets for the `turn` function:
   ```
   npx supabase secrets set TURN_SECRET="<static-auth-secret>"
   npx supabase secrets set TURN_URLS="turn:<ip-or-domain>:3478?transport=udp,turn:<ip-or-domain>:3478?transport=tcp,turns:<domain>:5349"
   ```
The app asks the function for a password valid for 6 hours before each call.
