import 'package:flutter/widgets.dart';

/// UI languages. Pashto is the default; Dari and English follow.
enum AppLang {
  ps('ps', 'پښتو'),
  fa('fa', 'دری'),
  en('en', 'English');

  const AppLang(this.code, this.label);
  final String code;
  final String label;

  bool get rtl => this != AppLang.en;

  static AppLang fromCode(String? code) =>
      AppLang.values.firstWhere((l) => l.code == code, orElse: () => AppLang.ps);
}

/// Small, dependency-free translation table.
/// Usage: `context.tr('chats')` or `Strings.of(lang).get('chats')`.
class Strings {
  const Strings(this.lang);
  final AppLang lang;

  String get(String key, [Map<String, String> args = const {}]) {
    final row = _t[key];
    var s = row == null ? key : (row[lang.code] ?? row['en'] ?? key);
    args.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  static const Map<String, Map<String, String>> _t = {
    // ── App & onboarding ──────────────────────────────────────────────────
    'app_name': {'ps': 'پیغام', 'fa': 'پیغام', 'en': 'Paigham'},
    'tagline': {
      'ps': 'د افغانانو خپل پیغام رسان',
      'fa': 'پیام‌رسانِ خودِ افغان‌ها',
      'en': 'The Afghan messenger',
    },
    'welcome_title': {'ps': 'پیغام ته ښه راغلاست', 'fa': 'به پیغام خوش آمدید', 'en': 'Welcome to Paigham'},
    'welcome_sub': {
      'ps': 'ګړندی، ساده او زموږ خپل. د افغانستان لپاره جوړ شوی پیغام رسان.',
      'fa': 'سریع، ساده و از خودمان. پیام‌رسانی ساخته‌شده برای افغانستان.',
      'en': 'Fast, simple and ours. A messenger built for Afghanistan.',
    },
    'choose_language': {'ps': 'ژبه وټاکئ', 'fa': 'زبان را انتخاب کنید', 'en': 'Choose your language'},
    'your_name': {'ps': 'ستاسو نوم', 'fa': 'نام شما', 'en': 'Your name'},
    'name_hint': {'ps': 'لکه: احمد شاه', 'fa': 'مثلاً: احمد شاه', 'en': 'e.g. Ahmad Shah'},
    'phone_optional': {'ps': 'د تلیفون شمېره (اختیاري)', 'fa': 'شمارهٔ تلفن (اختیاری)', 'en': 'Phone number (optional)'},
    'continue': {'ps': 'دوام', 'fa': 'ادامه', 'en': 'Continue'},
    'get_started': {'ps': 'پیل کړئ', 'fa': 'شروع کنید', 'en': 'Get started'},
    'create_profile': {'ps': 'خپله پاڼه جوړه کړئ', 'fa': 'پروفایل خود را بسازید', 'en': 'Create your profile'},
    'profile_note': {
      'ps': 'دا ازمایښتي نسخه ده. ستاسو نوم یوازې هغو کسانو ته ښکاري چې ورسره خبرې کوئ.',
      'fa': 'این نسخهٔ آزمایشی است. نام شما فقط برای کسانی دیده می‌شود که با آن‌ها گفتگو می‌کنید.',
      'en': 'This is a prototype. Your name is only shown to people you chat with.',
    },
    'name_required': {'ps': 'مهرباني وکړئ نوم ولیکئ', 'fa': 'لطفاً نام را بنویسید', 'en': 'Please enter a name'},

    // ── Navigation ────────────────────────────────────────────────────────
    'chats': {'ps': 'چټونه', 'fa': 'گفتگوها', 'en': 'Chats'},
    'calls': {'ps': 'زنګونه', 'fa': 'تماس‌ها', 'en': 'Calls'},
    'services': {'ps': 'خدمتونه', 'fa': 'خدمات', 'en': 'Services'},
    'settings': {'ps': 'ترتیبات', 'fa': 'تنظیمات', 'en': 'Settings'},

    // ── Connection ────────────────────────────────────────────────────────
    'connected': {'ps': 'وصل دی', 'fa': 'متصل', 'en': 'Connected'},
    'connecting': {'ps': 'نښلېږي...', 'fa': 'در حال اتصال...', 'en': 'Connecting...'},
    'offline': {'ps': 'انټرنېټ نشته', 'fa': 'آفلاین', 'en': 'Offline'},

    // ── Chat list ─────────────────────────────────────────────────────────
    'search': {'ps': 'لټون', 'fa': 'جستجو', 'en': 'Search'},
    'no_results': {'ps': 'هېڅ ونه موندل شو', 'fa': 'چیزی پیدا نشد', 'en': 'Nothing found'},
    'new_chat': {'ps': 'نوی چټ', 'fa': 'گفتگوی تازه', 'en': 'New chat'},
    'pinned': {'ps': 'ټاکل شوی', 'fa': 'سنجاق‌شده', 'en': 'Pinned'},
    'pin': {'ps': 'سر ته یې ونښلوئ', 'fa': 'سنجاق کردن', 'en': 'Pin'},
    'unpin': {'ps': 'له سره یې لرې کړئ', 'fa': 'برداشتن سنجاق', 'en': 'Unpin'},
    'delete_chat': {'ps': 'چټ ړنګول', 'fa': 'حذف گفتگو', 'en': 'Delete chat'},
    'delete_chat_q': {
      'ps': 'دا چټ او ټول پیغامونه یې له دې وسیلې ړنګ شي؟',
      'fa': 'این گفتگو و همهٔ پیام‌هایش از این دستگاه حذف شود؟',
      'en': 'Delete this chat and all its messages from this device?',
    },
    'delete': {'ps': 'ړنګول', 'fa': 'حذف', 'en': 'Delete'},
    'you': {'ps': 'تاسو', 'fa': 'شما', 'en': 'You'},
    'no_messages': {'ps': 'تر اوسه پیغام نشته', 'fa': 'هنوز پیامی نیست', 'en': 'No messages yet'},

    // ── Special chats ─────────────────────────────────────────────────────
    'lobby': {'ps': 'عمومي خونه', 'fa': 'اتاق عمومی', 'en': 'Public Lobby'},
    'lobby_sub': {
      'ps': 'ټول ازمایښتي کاروونکي دلته سره ګډ دي',
      'fa': 'همهٔ کاربران آزمایشی این‌جا با هم هستند',
      'en': 'Every prototype user can talk here',
    },
    'assistant': {'ps': 'مرستیال', 'fa': 'دستیار', 'en': 'Assistant'},
    'assistant_sub': {'ps': 'روبوټ', 'fa': 'ربات', 'en': 'bot'},
    'news': {'ps': 'د پیغام خبرونه', 'fa': 'خبرهای پیغام', 'en': 'Paigham News'},
    'news_sub': {'ps': 'رسمي چینل', 'fa': 'کانال رسمی', 'en': 'official channel'},
    'saved': {'ps': 'خوندي پیغامونه', 'fa': 'پیام‌های ذخیره‌شده', 'en': 'Saved Messages'},
    'saved_sub': {'ps': 'یوازې تاسو یې وینئ', 'fa': 'فقط شما می‌بینید', 'en': 'only you can see these'},
    'channel_readonly': {
      'ps': 'یوازې مدیران په دې چینل کې لیکلی شي',
      'fa': 'فقط مدیران در این کانال می‌نویسند',
      'en': 'Only admins can post in this channel',
    },

    // ── Built-in content ──────────────────────────────────────────────────
    'news_1': {
      'ps': 'پیغام ته ښه راغلاست!\nدا د افغانانو لپاره جوړ شوی پیغام رسان دی. له پښتو او دری سره پیل کوو او هڅه کوو چې په کمزوري انټرنېټ کې هم ګړندی کار وکړي.',
      'fa': 'به پیغام خوش آمدید!\nاین پیام‌رسانی است که برای افغان‌ها ساخته شده. با پشتو و دری شروع می‌کنیم و تلاش داریم با اینترنت ضعیف هم سریع کار کند.',
      'en': 'Welcome to Paigham!\nA messenger built for Afghans. We start with Pashto and Dari, and aim to stay fast even on weak internet.',
    },
    'news_2': {
      'ps': 'په دې لومړۍ نسخه کې:\n• یو بل ته پیغامونه د ID له لارې\n• ډلې او عمومي خونه\n• مرستیال روبوټ\n• هوا، د لمانځه وختونه، د اسعارو نرخ او د ورځې آیت\n• پښتو، دری او انګلیسي',
      'fa': 'در این نسخهٔ اول:\n• پیام مستقیم با شناسه\n• گروه‌ها و اتاق عمومی\n• ربات دستیار\n• آب‌وهوا، اوقات نماز، نرخ اسعار و آیهٔ روز\n• پشتو، دری و انگلیسی',
      'en': 'In this first version:\n• Direct messages by ID\n• Groups and a public lobby\n• Assistant bot\n• Weather, prayer times, exchange rates, verse of the day\n• Pashto, Dari and English',
    },
    'news_3': {
      'ps': 'راتلونکي ګامونه: غږیز پیغامونه، انځورونه، زنګونه، له سره تر پایه کوډ کول او زموږ خپل سرور.',
      'fa': 'گام‌های بعدی: پیام صوتی، عکس، تماس، رمزگذاری سرتاسری و سرور خودمان.',
      'en': 'Next up: voice notes, photos, calls, end-to-end encryption and our own server.',
    },
    'bot_hello': {
      'ps': 'سلام! زه مرستیال یم.\nما ته ولیکئ: هوا، نرخ، آیت، لمونځ یا نېټه.',
      'fa': 'سلام! من دستیار هستم.\nبرایم بنویسید: آب‌وهوا، نرخ، آیه، نماز یا تاریخ.',
      'en': 'Hi! I am the Assistant.\nTry: weather, rates, verse, prayer or date.',
    },
    'bot_help': {
      'ps': 'دا کلمې وازمویئ:\nهوا · نرخ · آیت · لمونځ · نېټه',
      'fa': 'این کلمه‌ها را امتحان کنید:\nآب‌وهوا · نرخ · آیه · نماز · تاریخ',
      'en': 'Try one of these:\nweather · rates · verse · prayer · date',
    },
    'lobby_welcome': {
      'ps': 'دا عمومي خونه ده. هر څوک چې پیغام نصب کړي دلته یې پیغام لیدلی شي.',
      'fa': 'این اتاق عمومی است. هر کسی که پیغام را نصب کند پیام‌های این‌جا را می‌بیند.',
      'en': 'This is the public lobby. Everyone who installs Paigham can read messages here.',
    },

    // ── New chat sheet ────────────────────────────────────────────────────
    'your_id': {'ps': 'ستاسو پېژند (ID)', 'fa': 'شناسهٔ شما (ID)', 'en': 'Your ID'},
    'share_id_hint': {
      'ps': 'دا ID خپلو ملګرو ته ولېږئ چې تاسو ته پیغام ولېږي',
      'fa': 'این شناسه را به دوستان‌تان بدهید تا به شما پیام بفرستند',
      'en': 'Share this ID so friends can message you',
    },
    'chat_with_id': {'ps': 'د ID له لارې خبرې', 'fa': 'گفتگو با شناسه', 'en': 'Chat by ID'},
    'friend_id': {'ps': 'د ملګري ID', 'fa': 'شناسهٔ دوست', 'en': "Friend's ID"},
    'friend_name': {'ps': 'د ملګري نوم (اختیاري)', 'fa': 'نام دوست (اختیاری)', 'en': "Friend's name (optional)"},
    'invalid_id': {'ps': 'دا ID سم نه دی', 'fa': 'این شناسه درست نیست', 'en': 'That ID is not valid'},
    'own_id': {'ps': 'دا ستاسو خپل ID دی', 'fa': 'این شناسهٔ خود شماست', 'en': 'That is your own ID'},
    'new_group': {'ps': 'نوې ډله', 'fa': 'گروه تازه', 'en': 'New group'},
    'group_name': {'ps': 'د ډلې نوم', 'fa': 'نام گروه', 'en': 'Group name'},
    'join_group': {'ps': 'ډلې ته ورګډېدل', 'fa': 'پیوستن به گروه', 'en': 'Join a group'},
    'group_code': {'ps': 'د ډلې کوډ', 'fa': 'کد گروه', 'en': 'Group code'},
    'invite_code': {'ps': 'د بلنې کوډ', 'fa': 'کد دعوت', 'en': 'Invite code'},
    'invite_hint': {
      'ps': 'دا کوډ ملګرو ته ورکړئ چې ډلې ته ورګډ شي',
      'fa': 'این کد را به دوستان بدهید تا به گروه بپیوندند',
      'en': 'Give this code to friends so they can join',
    },
    'create': {'ps': 'جوړول', 'fa': 'ساختن', 'en': 'Create'},
    'join': {'ps': 'ورګډېدل', 'fa': 'پیوستن', 'en': 'Join'},
    'start_chat': {'ps': 'چټ پیل کړئ', 'fa': 'شروع گفتگو', 'en': 'Start chat'},
    'cancel': {'ps': 'لغوه', 'fa': 'لغو', 'en': 'Cancel'},
    'ok': {'ps': 'سمه ده', 'fa': 'خوب', 'en': 'OK'},
    'copy': {'ps': 'کاپي', 'fa': 'کاپی', 'en': 'Copy'},
    'copied': {'ps': 'کاپي شو', 'fa': 'کاپی شد', 'en': 'Copied'},
    'show_qr': {'ps': 'QR کوډ', 'fa': 'کد QR', 'en': 'QR code'},

    // ── Conversation ──────────────────────────────────────────────────────
    'type_message': {'ps': 'پیغام ولیکئ...', 'fa': 'پیام بنویسید...', 'en': 'Message'},
    'today': {'ps': 'نن', 'fa': 'امروز', 'en': 'Today'},
    'yesterday': {'ps': 'پرون', 'fa': 'دیروز', 'en': 'Yesterday'},
    'members': {'ps': 'غړي', 'fa': 'اعضا', 'en': 'members'},
    'group': {'ps': 'ډله', 'fa': 'گروه', 'en': 'group'},
    'last_seen_unknown': {'ps': 'د پیغام کاروونکی', 'fa': 'کاربر پیغام', 'en': 'Paigham user'},
    'coming_soon': {'ps': 'دا برخه ډېر ژر راځي', 'fa': 'این بخش به‌زودی می‌آید', 'en': 'Coming soon'},
    'send_failed': {'ps': 'ونه لېږل شو. بیا هڅه وکړئ', 'fa': 'ارسال نشد. دوباره تلاش کنید', 'en': 'Not sent. Tap to retry'},
    'retry': {'ps': 'بیا هڅه', 'fa': 'تلاش دوباره', 'en': 'Retry'},
    'joined_group': {'ps': '{name} ډلې ته ورګډ شو', 'fa': '{name} به گروه پیوست', 'en': '{name} joined the group'},
    'group_created': {'ps': 'ډله جوړه شوه', 'fa': 'گروه ساخته شد', 'en': 'Group created'},
    'encryption_note': {
      'ps': 'ازمایښتي نسخه: پیغامونه لا پوره کوډ شوي نه دي. حساس معلومات مه لېږئ.',
      'fa': 'نسخهٔ آزمایشی: پیام‌ها هنوز کاملاً رمزگذاری نشده‌اند. اطلاعات حساس نفرستید.',
      'en': 'Prototype: messages are not end-to-end encrypted yet. Do not send sensitive data.',
    },

    // ── Calls ─────────────────────────────────────────────────────────────
    'calls_title': {'ps': 'غږیز او ویډیويي زنګونه', 'fa': 'تماس صوتی و تصویری', 'en': 'Voice & video calls'},
    'calls_body': {
      'ps': 'زنګونه به په دوهم پړاو کې د خپل سرور سره راشي، داسې چې په کمزوري انټرنېټ کې هم ښه کار وکړي.',
      'fa': 'تماس‌ها در مرحلهٔ دوم با سرور خودمان می‌آیند و طوری ساخته می‌شوند که با اینترنت ضعیف هم کار کنند.',
      'en': 'Calls arrive in phase two with our own server, tuned to work on weak connections.',
    },
    'roadmap': {'ps': 'راتلونکي ګامونه', 'fa': 'گام‌های بعدی', 'en': 'Roadmap'},
    'rm_calls': {'ps': 'غږیز زنګونه (WebRTC)', 'fa': 'تماس صوتی (WebRTC)', 'en': 'Voice calls (WebRTC)'},
    'rm_video': {'ps': 'ویډیويي زنګونه', 'fa': 'تماس تصویری', 'en': 'Video calls'},
    'rm_voice_notes': {'ps': 'غږیز پیغامونه', 'fa': 'پیام صوتی', 'en': 'Voice notes'},
    'rm_media': {'ps': 'انځورونه او فایلونه', 'fa': 'عکس و فایل', 'en': 'Photos & files'},
    'rm_e2e': {'ps': 'له سره تر پایه کوډ کول', 'fa': 'رمزگذاری سرتاسری', 'en': 'End-to-end encryption'},
    'rm_server': {'ps': 'خپل سرور او پېژند په SMS', 'fa': 'سرور خودی و تأیید با SMS', 'en': 'Own server & SMS sign-in'},

    // ── Services ──────────────────────────────────────────────────────────
    'weather': {'ps': 'هوا', 'fa': 'آب‌وهوا', 'en': 'Weather'},
    'prayer_times': {'ps': 'د لمانځه وختونه', 'fa': 'اوقات نماز', 'en': 'Prayer times'},
    'rates': {'ps': 'د اسعارو نرخونه', 'fa': 'نرخ اسعار', 'en': 'Exchange rates'},
    'rates_sub': {'ps': 'په افغانیو', 'fa': 'به افغانی', 'en': 'in Afghani'},
    'ayah': {'ps': 'د ورځې آیت', 'fa': 'آیهٔ روز', 'en': 'Verse of the day'},
    'city': {'ps': 'ښار', 'fa': 'شهر', 'en': 'City'},
    'loading': {'ps': 'راوړل کېږي...', 'fa': 'در حال دریافت...', 'en': 'Loading...'},
    'load_failed': {'ps': 'معلومات رانه وړل شول', 'fa': 'اطلاعات دریافت نشد', 'en': 'Could not load'},
    'wind': {'ps': 'باد', 'fa': 'باد', 'en': 'Wind'},
    'humidity': {'ps': 'لوندوالی', 'fa': 'رطوبت', 'en': 'Humidity'},
    'feels_like': {'ps': 'احساس', 'fa': 'احساس', 'en': 'Feels'},
    'fajr': {'ps': 'سهار', 'fa': 'صبح', 'en': 'Fajr'},
    'sunrise': {'ps': 'لمر ختل', 'fa': 'طلوع', 'en': 'Sunrise'},
    'dhuhr': {'ps': 'ماسپښین', 'fa': 'پیشین', 'en': 'Dhuhr'},
    'asr': {'ps': 'مازدیګر', 'fa': 'دیگر', 'en': 'Asr'},
    'maghrib': {'ps': 'ماښام', 'fa': 'شام', 'en': 'Maghrib'},
    'isha': {'ps': 'ماخستن', 'fa': 'خفتن', 'en': 'Isha'},
    'source': {'ps': 'سرچینه', 'fa': 'منبع', 'en': 'Source'},
    'afghani': {'ps': 'افغانۍ', 'fa': 'افغانی', 'en': 'AFN'},

    // ── Settings ──────────────────────────────────────────────────────────
    'language': {'ps': 'ژبه', 'fa': 'زبان', 'en': 'Language'},
    'theme': {'ps': 'بڼه', 'fa': 'نما', 'en': 'Appearance'},
    'theme_system': {'ps': 'د وسیلې په څېر', 'fa': 'مطابق دستگاه', 'en': 'System'},
    'theme_light': {'ps': 'روښانه', 'fa': 'روشن', 'en': 'Light'},
    'theme_dark': {'ps': 'تیاره', 'fa': 'تاریک', 'en': 'Dark'},
    'notifications': {'ps': 'خبرتیاوې', 'fa': 'اعلان‌ها', 'en': 'Notifications'},
    'privacy': {'ps': 'محرمیت او امنیت', 'fa': 'حریم خصوصی و امنیت', 'en': 'Privacy & security'},
    'relay_server': {'ps': 'سرور', 'fa': 'سرور', 'en': 'Server'},
    'relay_hint': {
      'ps': 'اوس وړیا ntfy.sh کاروو. کله چې خپل سرور واخلو، دلته یې پته بدلوو.',
      'fa': 'فعلاً از ntfy.sh رایگان استفاده می‌کنیم. وقتی سرور خود را بخریم، آدرس را این‌جا عوض می‌کنیم.',
      'en': 'Using free ntfy.sh for now. When we buy our own server, change the address here.',
    },
    'about': {'ps': 'د پیغام په اړه', 'fa': 'دربارهٔ پیغام', 'en': 'About Paigham'},
    'version': {'ps': 'نسخه', 'fa': 'نسخه', 'en': 'Version'},
    'free_services': {'ps': 'کارول شوي وړیا خدمتونه', 'fa': 'خدمات رایگانِ استفاده‌شده', 'en': 'Free services in use'},
    'reset_app': {'ps': 'ټول معلومات پاکول', 'fa': 'پاک کردن همهٔ داده‌ها', 'en': 'Erase all data'},
    'reset_q': {
      'ps': 'ستاسو پاڼه او ټول چټونه له دې وسیلې پاک شي؟',
      'fa': 'پروفایل و همهٔ گفتگوها از این دستگاه پاک شوند؟',
      'en': 'Erase your profile and all chats from this device?',
    },
    'save': {'ps': 'ساتل', 'fa': 'ذخیره', 'en': 'Save'},
    'edit_name': {'ps': 'نوم بدلول', 'fa': 'تغییر نام', 'en': 'Edit name'},
    'prototype': {'ps': 'ازمایښتي نسخه', 'fa': 'نسخهٔ آزمایشی', 'en': 'Prototype'},
    'made_for': {'ps': 'د افغانستان لپاره جوړ شوی', 'fa': 'ساخته‌شده برای افغانستان', 'en': 'Made for Afghanistan'},
    'select_chat': {
      'ps': 'یو چټ وټاکئ او خبرې پیل کړئ',
      'fa': 'یک گفتگو را انتخاب کنید و شروع کنید',
      'en': 'Pick a chat to start messaging',
    },
  };
}

/// Holds the active language for the widget tree.
class LangScope extends InheritedWidget {
  const LangScope({super.key, required this.lang, required super.child});
  final AppLang lang;

  static AppLang of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LangScope>()?.lang ?? AppLang.ps;

  @override
  bool updateShouldNotify(LangScope old) => old.lang != lang;
}

extension TrX on BuildContext {
  AppLang get lang => LangScope.of(this);
  String tr(String key, [Map<String, String> args = const {}]) => Strings(lang).get(key, args);

  /// Converts Western digits to Eastern Arabic-Indic digits for Pashto/Dari.
  String digits(Object value) => localDigits(value.toString(), lang);
}

String localDigits(String s, AppLang lang) {
  if (lang == AppLang.en) return s;
  // Persian/Pashto decimal separator: 65.55 -> ۶۵٫۵۵
  s = s.replaceAllMapped(RegExp(r'(\d)\.(\d)'), (m) => '${m[1]}\u066B${m[2]}');
  const western = '0123456789';
  const eastern = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = western.indexOf(ch);
    b.write(i >= 0 ? eastern[i] : ch);
  }
  return b.toString();
}
