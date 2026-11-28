# د خبرتیاوو (Push) جوړول — ګام په ګام

دا لارښود د دې لپاره دی چې کله اپ بند وي، بیا هم د نوي پیغام او زنګ
خبرتیا راشي. ټول کار په براوزر کې کېږي (کمپیوټر ښه دی، خو تلیفون هم کار
کوي). هېڅ پروګرام نصبولو ته اړتیا نشته.

پوره کار شاوخوا ۲۰ دقیقې نیسي. درې برخې لري:

| برخه | چېرته | څه کېږي |
|---|---|---|
| A | Firebase | د خبرتیا لېږلو حساب جوړول |
| B | Supabase | سرور ته ویل چې خبرتیا ولېږي |
| C | پراختیاکوونکی (زه) | APK د Firebase معلوماتو سره بیا جوړول |

---

## A — Firebase

### A1. پروژه جوړول
1. براوزر کې دا پاڼه خلاصه کړئ: **https://console.firebase.google.com**
2. د خپل Google (Gmail) حساب سره ننوځئ.
3. په **Create a project** (یا **Get started with a Firebase project**) کلیک وکړئ.
4. نوم ولیکئ: `Paigham` ← **Continue**.
5. که د Gemini یا AI پوښتنه وشوه ← **Continue**.
6. **Google Analytics**: سویچ بند کړئ (اړتیا نشته) ← **Create project**.
7. انتظار وکړئ ← **Continue**.

### A2. د Android اپ ورزیاتول
1. د پروژې په لومړۍ پاڼه کې د **Android** نښه (شین روبوټ) کلیک کړئ.
   (که نه ښکاري: **+ Add app** ← **Android**.)
2. **Android package name** کې دقیق دا ولیکئ:
   ```
   af.paigham.messenger
   ```
3. **App nickname**: `Paigham` (اختیاري). **SHA-1** خالي پرېږدئ.
4. **Register app** کلیک کړئ.
5. **Download google-services.json** کلیک کړئ. فایل ښکته کېږي.
6. **Next** ← **Next** ← **Continue to console** (پاتې ګامونه ما کړي دي).

### A3. پټ کیلي (Service account) اخیستل
1. پورته کیڼ لور کې د ⚙ (ګیر) نښه ← **Project settings**.
2. پورته **Service accounts** ټب.
3. **Generate new private key** ← **Generate key**.
4. یو `.json` فایل ښکته کېږي (نوم یې داسې وي: `paigham-xxxxx-firebase-adminsdk-....json`).

> ⚠ دا فایل **پټ** دی. هېچا ته یې مه لېږئ، ماته هم نه. یوازې په B3 ګام کې
> یې په Supabase کې ږدئ.

---

## B — Supabase

### B1. د ډیټابېس بدلونونه (SQL)
1. **https://supabase.com/dashboard** ← خپله پروژه خلاصه کړئ.
2. کیڼ لور مینو ← **SQL Editor** ← **+ New query**.
3. که مو v10 لا نه وي چلولی، لومړی دا فایل خلاص کړئ، ټول متن یې کاپي کړئ،
   په SQL Editor کې یې پېسټ کړئ او **Run** ووهئ:
   https://github.com/ElyasOmarcodes/Messenger-App/blob/ccr-249cf137-0a1iue/backend/supabase/migrations/20261201000000_paigham_v10.sql
   (په GitHub کې د فایل پورته ښي لور کې د **Copy raw file** تڼۍ شته.)
4. بیا یوه نوې query ← همدا کار د v11 سره:
   https://github.com/ElyasOmarcodes/Messenger-App/blob/ccr-249cf137-0a1iue/backend/supabase/migrations/20261202000000_paigham_v11.sql
5. باید **Success. No rows returned** وښيي.

### B2. د `push` فنکشن جوړول
1. کیڼ لور مینو ← **Edge Functions**.
2. **Deploy a new function** ← **Via Editor**.
3. د فنکشن نوم دقیق: `push`
4. په ایډیټر کې چې کوم کوډ دی، ټول یې پاک کړئ (Ctrl+A ← Delete).
5. دا فایل خلاص کړئ، ټول متن یې کاپي کړئ او په ایډیټر کې پېسټ کړئ:
   https://github.com/ElyasOmarcodes/Messenger-App/blob/ccr-249cf137-0a1iue/backend/supabase/functions/push/index.ts
6. **Deploy function** کلیک کړئ او انتظار وکړئ.
7. د `push` فنکشن پاڼه کې ← **Details** (یا **Settings**) ← **Enforce JWT
   Verification** (یا **Verify JWT**) سویچ **بند** کړئ ← **Save**.
   (ډیټابېس دا فنکشن د خپل پټ رمز سره غږوي، نه د JWT سره.)

### B3. پټ معلومات (Secrets)
1. **Edge Functions** ← **Secrets** (یا: **Project Settings** ← **Edge Functions**).
2. **Add new secret**:
   - **Name**: `FCM_SERVICE_ACCOUNT`
   - **Value**: د A3 فایل په Notepad (یا بل متن ایډیټر) کې خلاص کړئ، **ټول**
     متن یې کاپي کړئ (له `{` نه تر `}` پورې) او دلته یې پېسټ کړئ.
   - **Save**.
3. بیا **Add new secret**:
   - **Name**: `PUSH_SECRET`
   - **Value**: یو اوږد ناڅاپي رمز جوړ کړئ، لږ تر لږه ۳۲ توري او شمېرې،
     بې تشې. د بېلګې په توګه: `k7Qm2x9WpL4vR8tZ3nB6yH1cD5fJ0sAe`
     (دا بېلګه مه کاروئ، خپل یې جوړ کړئ). **دا رمز یاد وساتئ**، په B4 کې ورته اړتیا ده.
   - **Save**.

### B4. ډیټابېس ته ویل چې فنکشن چېرته دی
1. **SQL Editor** ← **+ New query**.
2. دا متن پېسټ کړئ. په دویمه کرښه کې `<PUSH_SECRET>` د B3 رمز سره بدل کړئ
   (`'` نښې پرېږدئ):
   ```sql
   insert into push_config (id, url, secret)
   values (1, 'https://dspcumnbqyxwtxtljpub.supabase.co/functions/v1/push', '<PUSH_SECRET>')
   on conflict (id) do update set url = excluded.url, secret = excluded.secret;
   ```
3. **Run** ← باید **Success** وښيي.

---

## C — ماته لېږل

د A2 فایل `google-services.json` په Notepad کې خلاص کړئ، ټول متن یې کاپي کړئ
او ماته یې په چټ کې راولېږئ.

دا فایل **پټ نه دی** (یوازې د پروژې نوم او عامه کیلي لري). د A3 فایل سره یې
مه ګډوئ. هغه پټ دی.

زه به بیا APK د دې معلوماتو سره جوړ کړم.

---

## D — په تلیفون کې

1. نوی APK نصب کړئ او اپ خلاص کړئ.
2. کله چې د **خبرتیاوو اجازه** وغوښتل شي ← **Allow**.
3. ډېرې شیاومي، سامسونګ او نور تلیفونونه شاته اپونه بندوي:
   **Settings ← Apps ← Paigham ← Battery** ← **Unrestricted** (یا **No restrictions**).
   په شیاومي کې: **Autostart** هم روښانه کړئ.
4. ازمېښت: اپ په بشپړه توګه بند کړئ. له بل حساب څخه پیغام ولېږئ. خبرتیا
   باید په څو ثانیو کې راشي.

## که خبرتیا رانغله

- **Edge Functions ← push ← Logs** وګورئ:
  - که هېڅ نه وي، نو B4 یا v11 سم نه دي شوي.
  - که `401` وي، نو د B4 رمز او د B3 `PUSH_SECRET` یو شان نه دي، یا د JWT سویچ (B2.7) لا روښانه دی.
- د ښکاره شوې تېروتنې متن ماته راولېږئ. خو پټ رمزونه مه لېږئ.
