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
    // ── App ───────────────────────────────────────────────────────────────
    'app_name': {'ps': 'پیغام', 'fa': 'پیغام', 'en': 'Paigham'},
    'tagline': {'ps': 'د افغانانو خپل پیغام رسان', 'fa': 'پیام‌رسانِ خودِ افغان‌ها', 'en': 'The Afghan messenger'},
    'welcome_title': {'ps': 'پیغام ته ښه راغلاست', 'fa': 'به پیغام خوش آمدید', 'en': 'Welcome to Paigham'},
    'welcome_sub': {
      'ps': 'پیغامونه، انځورونه او فایلونه ولېږئ. ګړندی، ساده او زموږ خپل.',
      'fa': 'پیام، عکس و فایل بفرستید. سریع، ساده و از خودمان.',
      'en': 'Send messages, photos and files. Fast, simple and ours.',
    },
    'choose_language': {'ps': 'ژبه وټاکئ', 'fa': 'زبان را انتخاب کنید', 'en': 'Choose your language'},
    'server_missing': {
      'ps': 'د سرور پته او کیلي یو ځل ولیکئ (د Supabase پروژې له Settings → API څخه).',
      'fa': 'آدرس و کلید سرور را یک بار بنویسید (از Settings → API پروژهٔ Supabase).',
      'en': 'Enter your server address and key once (Supabase project → Settings → API).',
    },
    'connect': {'ps': 'وصلول', 'fa': 'اتصال', 'en': 'Connect'},

    // ── Auth ──────────────────────────────────────────────────────────────
    'login': {'ps': 'ننوتل', 'fa': 'ورود', 'en': 'Log in'},
    'signup': {'ps': 'نوی حساب', 'fa': 'حساب تازه', 'en': 'Sign up'},
    'logout': {'ps': 'وتل', 'fa': 'خروج', 'en': 'Log out'},
    'logout_q': {'ps': 'له حساب څخه ووځئ؟', 'fa': 'از حساب خارج می‌شوید؟', 'en': 'Log out of your account?'},
    'email': {'ps': 'ایمیل', 'fa': 'ایمیل', 'en': 'Email'},
    'password': {'ps': 'پټنوم', 'fa': 'رمز عبور', 'en': 'Password'},
    'new_password': {'ps': 'نوی پټنوم', 'fa': 'رمز تازه', 'en': 'New password'},
    'your_name': {'ps': 'ستاسو نوم', 'fa': 'نام شما', 'en': 'Your name'},
    'name_hint': {'ps': 'لکه: احمد شاه', 'fa': 'مثلاً: احمد شاه', 'en': 'e.g. Ahmad Shah'},
    'forgot': {'ps': 'پټنوم مو هېر شوی؟', 'fa': 'رمز را فراموش کرده‌اید؟', 'en': 'Forgot password?'},
    'no_account': {'ps': 'حساب نه لرئ؟ نوی جوړ کړئ', 'fa': 'حساب ندارید؟ بسازید', 'en': "No account? Sign up"},
    'have_account': {'ps': 'حساب لرئ؟ ننوځئ', 'fa': 'حساب دارید؟ وارد شوید', 'en': 'Have an account? Log in'},
    'create_account': {'ps': 'حساب جوړول', 'fa': 'ساختن حساب', 'en': 'Create account'},
    'verify_title': {'ps': 'خپل ایمیل تایید کړئ', 'fa': 'ایمیل خود را تأیید کنید', 'en': 'Confirm your email'},
    'verify_sub': {
      'ps': 'موږ {email} ته ۶ عددي کوډ ولېږه. هغه دلته ولیکئ.',
      'fa': 'یک کد ۶ رقمی به {email} فرستادیم. آن را این‌جا بنویسید.',
      'en': 'We sent a 6-digit code to {email}. Enter it here.',
    },
    'code': {'ps': 'کوډ', 'fa': 'کد', 'en': 'Code'},
    'verify': {'ps': 'تایید', 'fa': 'تأیید', 'en': 'Confirm'},
    'resend': {'ps': 'کوډ بیا ولېږئ', 'fa': 'ارسال دوبارهٔ کد', 'en': 'Resend code'},
    'code_sent': {'ps': 'کوډ ولېږل شو', 'fa': 'کد فرستاده شد', 'en': 'Code sent'},
    'reset_title': {'ps': 'پټنوم بدلول', 'fa': 'تغییر رمز', 'en': 'Reset password'},
    'reset_sub': {
      'ps': 'خپل ایمیل ولیکئ، موږ به درته کوډ ولېږو.',
      'fa': 'ایمیل خود را بنویسید تا برایتان کد بفرستیم.',
      'en': 'Enter your email and we will send you a code.',
    },
    'send_code': {'ps': 'کوډ ولېږئ', 'fa': 'فرستادن کد', 'en': 'Send code'},
    'save_password': {'ps': 'پټنوم وساتئ', 'fa': 'ذخیرهٔ رمز', 'en': 'Save password'},
    'err_email': {'ps': 'سم ایمیل ولیکئ', 'fa': 'ایمیل درست بنویسید', 'en': 'Enter a valid email'},
    'err_password': {'ps': 'پټنوم لږ تر لږه ۸ توري وي', 'fa': 'رمز حداقل ۸ حرف باشد', 'en': 'Password must be at least 8 characters'},
    'err_name': {'ps': 'مهرباني وکړئ نوم ولیکئ', 'fa': 'لطفاً نام را بنویسید', 'en': 'Please enter a name'},
    'err_code': {'ps': 'کوډ سم نه دی یا یې وخت تېر شوی', 'fa': 'کد نادرست یا منقضی است', 'en': 'Wrong or expired code'},
    'err_login': {'ps': 'ایمیل یا پټنوم سم نه دی', 'fa': 'ایمیل یا رمز نادرست است', 'en': 'Wrong email or password'},
    'err_exists': {'ps': 'په دې ایمیل مخکې حساب جوړ شوی', 'fa': 'با این ایمیل قبلاً حساب ساخته شده', 'en': 'An account with this email already exists'},
    'err_network': {'ps': 'سرور ته نښلېدل ونه شول. انټرنېټ وګورئ', 'fa': 'اتصال به سرور ممکن نشد. اینترنت را بررسی کنید', 'en': 'Could not reach the server. Check your internet'},
    'err_generic': {'ps': 'یوه ستونزه پېښه شوه. بیا هڅه وکړئ', 'fa': 'مشکلی پیش آمد. دوباره تلاش کنید', 'en': 'Something went wrong. Try again'},

    // ── Navigation ────────────────────────────────────────────────────────
    'chats': {'ps': 'چټونه', 'fa': 'گفتگوها', 'en': 'Chats'},
    'calls': {'ps': 'زنګونه', 'fa': 'تماس‌ها', 'en': 'Calls'},
    'settings': {'ps': 'ترتیبات', 'fa': 'تنظیمات', 'en': 'Settings'},
    'connected': {'ps': 'وصل دی', 'fa': 'متصل', 'en': 'Connected'},
    'connecting': {'ps': 'نښلېږي...', 'fa': 'در حال اتصال...', 'en': 'Connecting...'},

    // ── Chat list ─────────────────────────────────────────────────────────
    'search': {'ps': 'لټون', 'fa': 'جستجو', 'en': 'Search'},
    'no_results': {'ps': 'هېڅ ونه موندل شو', 'fa': 'چیزی پیدا نشد', 'en': 'Nothing found'},
    'no_chats': {'ps': 'تر اوسه چټ نشته', 'fa': 'هنوز گفتگویی نیست', 'en': 'No chats yet'},
    'no_chats_sub': {
      'ps': 'د ✏️ تڼۍ کېکاږئ او د ملګري ایمیل ولیکئ.',
      'fa': 'دکمهٔ ✏️ را بزنید و ایمیل دوست‌تان را بنویسید.',
      'en': "Tap ✏️ and enter a friend's email.",
    },
    'new_chat': {'ps': 'نوی چټ', 'fa': 'گفتگوی تازه', 'en': 'New chat'},
    'you': {'ps': 'تاسو', 'fa': 'شما', 'en': 'You'},
    'no_messages': {'ps': 'تر اوسه پیغام نشته', 'fa': 'هنوز پیامی نیست', 'en': 'No messages yet'},
    'photo': {'ps': 'انځور', 'fa': 'عکس', 'en': 'Photo'},
    'file': {'ps': 'فایل', 'fa': 'فایل', 'en': 'File'},
    'leave_chat': {'ps': 'له چټ څخه وتل', 'fa': 'ترک گفتگو', 'en': 'Leave chat'},
    'leave_q': {'ps': 'له دې چټ څخه ووځئ؟', 'fa': 'از این گفتگو خارج می‌شوید؟', 'en': 'Leave this chat?'},
    'leave': {'ps': 'وتل', 'fa': 'خروج', 'en': 'Leave'},

    // ── New chat ──────────────────────────────────────────────────────────
    'find_person': {'ps': 'د ایمیل یا کارن نوم له لارې', 'fa': 'با ایمیل یا نام کاربری', 'en': 'By email or username'},
    'find_hint': {'ps': 'ایمیل یا @کارن‌نوم', 'fa': 'ایمیل یا @نام‌کاربری', 'en': 'email or @username'},
    'find': {'ps': 'موندل', 'fa': 'یافتن', 'en': 'Find'},
    'not_found': {
      'ps': 'دا کس په پیغام کې حساب نه لري. ورته ووایاست چې پیغام نصب کړي.',
      'fa': 'این شخص در پیغام حساب ندارد. به او بگویید پیغام را نصب کند.',
      'en': 'No Paigham account found. Invite them to install Paigham.',
    },
    'start_chat': {'ps': 'چټ پیل کړئ', 'fa': 'شروع گفتگو', 'en': 'Start chat'},
    'new_group': {'ps': 'نوې ډله', 'fa': 'گروه تازه', 'en': 'New group'},
    'group_name': {'ps': 'د ډلې نوم', 'fa': 'نام گروه', 'en': 'Group name'},
    'add_members': {'ps': 'غړي ورزیات کړئ', 'fa': 'افزودن اعضا', 'en': 'Add members'},
    'add_member': {'ps': 'غړی ورزیاتول', 'fa': 'افزودن عضو', 'en': 'Add member'},
    'added': {'ps': 'ورزیات شو', 'fa': 'افزوده شد', 'en': 'Added'},
    'create': {'ps': 'جوړول', 'fa': 'ساختن', 'en': 'Create'},
    'add': {'ps': 'زیاتول', 'fa': 'افزودن', 'en': 'Add'},
    'cancel': {'ps': 'لغوه', 'fa': 'لغو', 'en': 'Cancel'},
    'ok': {'ps': 'سمه ده', 'fa': 'خوب', 'en': 'OK'},
    'copied': {'ps': 'کاپي شو', 'fa': 'کاپی شد', 'en': 'Copied'},

    // ── Conversation ──────────────────────────────────────────────────────
    'type_message': {'ps': 'پیغام ولیکئ...', 'fa': 'پیام بنویسید...', 'en': 'Message'},
    'today': {'ps': 'نن', 'fa': 'امروز', 'en': 'Today'},
    'yesterday': {'ps': 'پرون', 'fa': 'دیروز', 'en': 'Yesterday'},
    'members': {'ps': 'غړي', 'fa': 'عضو', 'en': 'members'},
    'attach_photo': {'ps': 'انځور', 'fa': 'عکس', 'en': 'Photo'},
    'attach_file': {'ps': 'سند / فایل', 'fa': 'سند / فایل', 'en': 'Document'},
    'uploading': {'ps': 'پورته کېږي...', 'fa': 'در حال بارگذاری...', 'en': 'Uploading...'},
    'too_big': {'ps': 'فایل له ۵۰ MB لوی دی', 'fa': 'فایل بزرگ‌تر از ۵۰ MB است', 'en': 'File is larger than 50 MB'},
    'open': {'ps': 'پرانیستل', 'fa': 'باز کردن', 'en': 'Open'},
    'send_failed': {'ps': 'ونه لېږل شو. د بیا هڅې لپاره کېکاږئ', 'fa': 'ارسال نشد. برای تلاش دوباره بزنید', 'en': 'Not sent. Tap to retry'},
    'coming_soon': {'ps': 'دا برخه ډېر ژر راځي', 'fa': 'این بخش به‌زودی می‌آید', 'en': 'Coming soon'},
    'group_created': {'ps': 'ډله جوړه شوه', 'fa': 'گروه ساخته شد', 'en': 'Group created'},
    'say_hello': {'ps': 'سلام ووایاست 👋', 'fa': 'سلام کنید 👋', 'en': 'Say hello 👋'},

    // ── Calls ─────────────────────────────────────────────────────────────
    'calls_title': {'ps': 'غږیز او ویډیويي زنګونه', 'fa': 'تماس صوتی و تصویری', 'en': 'Voice & video calls'},
    'calls_body': {
      'ps': 'زنګونه په راتلونکي پړاو کې راځي، داسې چې په کمزوري انټرنېټ کې هم ښه کار وکړي.',
      'fa': 'تماس‌ها در مرحلهٔ بعد می‌آیند و طوری ساخته می‌شوند که با اینترنت ضعیف هم کار کنند.',
      'en': 'Calls arrive in the next phase, tuned to work on weak connections.',
    },
    'roadmap': {'ps': 'راتلونکي ګامونه', 'fa': 'گام‌های بعدی', 'en': 'Roadmap'},
    'rm_calls': {'ps': 'غږیز زنګونه', 'fa': 'تماس صوتی', 'en': 'Voice calls'},
    'rm_video': {'ps': 'ویډیويي زنګونه', 'fa': 'تماس تصویری', 'en': 'Video calls'},
    'rm_voice_notes': {'ps': 'غږیز پیغامونه', 'fa': 'پیام صوتی', 'en': 'Voice notes'},
    'rm_push': {'ps': 'خبرتیاوې (notifications)', 'fa': 'اعلان‌ها', 'en': 'Push notifications'},
    'rm_e2e': {'ps': 'له سره تر پایه کوډ کول', 'fa': 'رمزگذاری سرتاسری', 'en': 'End-to-end encryption'},

    // ── Settings ──────────────────────────────────────────────────────────
    'profile': {'ps': 'پاڼه', 'fa': 'پروفایل', 'en': 'Profile'},
    'username': {'ps': 'کارن نوم', 'fa': 'نام کاربری', 'en': 'Username'},
    'username_hint': {
      'ps': 'یوازې انګلیسي توري، عدد او _ (۳ تر ۲۴)',
      'fa': 'فقط حروف انگلیسی، عدد و _ (۳ تا ۲۴)',
      'en': 'Letters a–z, digits and _ (3–24)',
    },
    'username_taken': {'ps': 'دا کارن نوم نیول شوی یا سم نه دی', 'fa': 'این نام کاربری گرفته شده یا نادرست است', 'en': 'Username taken or invalid'},
    'not_set': {'ps': 'نه دی ټاکل شوی', 'fa': 'تنظیم نشده', 'en': 'Not set'},
    'edit_name': {'ps': 'نوم بدلول', 'fa': 'تغییر نام', 'en': 'Edit name'},
    'save': {'ps': 'ساتل', 'fa': 'ذخیره', 'en': 'Save'},
    'language': {'ps': 'ژبه', 'fa': 'زبان', 'en': 'Language'},
    'theme': {'ps': 'بڼه', 'fa': 'نما', 'en': 'Appearance'},
    'theme_system': {'ps': 'د وسیلې په څېر', 'fa': 'مطابق دستگاه', 'en': 'System'},
    'theme_light': {'ps': 'روښانه', 'fa': 'روشن', 'en': 'Light'},
    'theme_dark': {'ps': 'تیاره', 'fa': 'تاریک', 'en': 'Dark'},
    'privacy': {'ps': 'محرمیت او امنیت', 'fa': 'حریم خصوصی و امنیت', 'en': 'Privacy & security'},
    'privacy_body': {
      'ps': 'یوازې د چټ غړي د هغه پیغامونه او فایلونه لیدلی شي. ټول اړیکې په HTTPS کوډ شوي دي. له سره تر پایه کوډ کول به په راتلونکي نسخه کې راشي.',
      'fa': 'فقط اعضای هر گفتگو پیام‌ها و فایل‌های آن را می‌بینند. همهٔ ارتباطات با HTTPS رمزگذاری شده. رمزگذاری سرتاسری در نسخهٔ بعدی می‌آید.',
      'en': 'Only members of a chat can see its messages and files. All traffic is encrypted with HTTPS. End-to-end encryption comes in a later version.',
    },
    'server': {'ps': 'سرور', 'fa': 'سرور', 'en': 'Server'},
    'about': {'ps': 'د پیغام په اړه', 'fa': 'دربارهٔ پیغام', 'en': 'About Paigham'},
    'version': {'ps': 'نسخه', 'fa': 'نسخه', 'en': 'Version'},
    'prototype': {'ps': 'ازمایښتي نسخه', 'fa': 'نسخهٔ آزمایشی', 'en': 'Prototype'},
    'made_for': {'ps': 'د افغانستان لپاره جوړ شوی', 'fa': 'ساخته‌شده برای افغانستان', 'en': 'Made for Afghanistan'},
    'select_chat': {'ps': 'یو چټ وټاکئ او خبرې پیل کړئ', 'fa': 'یک گفتگو را انتخاب کنید', 'en': 'Pick a chat to start messaging'},
    // ── v0.3: replies, delete, voice, photo, calls ────────────────────────
    'reply': {'ps': 'ځواب', 'fa': 'پاسخ', 'en': 'Reply'},
    'copy': {'ps': 'کاپي', 'fa': 'کپی', 'en': 'Copy'},
    'delete': {'ps': 'ړنګول', 'fa': 'حذف', 'en': 'Delete'},
    'delete_q': {'ps': 'دا پیغام د ټولو لپاره ړنګ شي؟', 'fa': 'این پیام برای همه حذف شود؟', 'en': 'Delete this message for everyone?'},
    'deleted': {'ps': 'دا پیغام ړنګ شو', 'fa': 'این پیام حذف شد', 'en': 'This message was deleted'},
    'voice_message': {'ps': 'غږیز پیغام', 'fa': 'پیام صوتی', 'en': 'Voice message'},
    'recording': {'ps': 'ثبتېږي...', 'fa': 'در حال ضبط...', 'en': 'Recording...'},
    'mic_denied': {'ps': 'مایکروفون ته اجازه ورکړئ', 'fa': 'اجازهٔ میکروفون را بدهید', 'en': 'Allow microphone access'},
    'change_photo': {'ps': 'انځور بدلول', 'fa': 'تغییر عکس', 'en': 'Change photo'},
    'photo_too_big': {'ps': 'انځور باید له ۵ MB کوچنی وي', 'fa': 'عکس باید کمتر از ۵ MB باشد', 'en': 'Photo must be under 5 MB'},
    'voice_call': {'ps': 'غږیز زنګ', 'fa': 'تماس صوتی', 'en': 'Voice call'},
    'video_call': {'ps': 'ویډیويي زنګ', 'fa': 'تماس تصویری', 'en': 'Video call'},
    'incoming_voice': {'ps': 'غږیز زنګ راځي', 'fa': 'تماس صوتی ورودی', 'en': 'Incoming voice call'},
    'incoming_video': {'ps': 'ویډیويي زنګ راځي', 'fa': 'تماس تصویری ورودی', 'en': 'Incoming video call'},
    'calling': {'ps': 'زنګ وهل کېږي...', 'fa': 'در حال تماس...', 'en': 'Calling...'},
    'connecting_call': {'ps': 'وصلېږي...', 'fa': 'در حال اتصال...', 'en': 'Connecting...'},
    'accept': {'ps': 'منل', 'fa': 'پذیرفتن', 'en': 'Accept'},
    'decline': {'ps': 'ردول', 'fa': 'رد کردن', 'en': 'Decline'},
    'call_ended': {'ps': 'زنګ پای ته ورسېد', 'fa': 'تماس پایان یافت', 'en': 'Call ended'},
    'call_declined': {'ps': 'زنګ رد شو', 'fa': 'تماس رد شد', 'en': 'Call declined'},
    'call_missed': {'ps': 'ځواب یې ورنه کړ', 'fa': 'پاسخ داده نشد', 'en': 'No answer'},
    'call_failed': {'ps': 'زنګ ونه شو. انټرنېټ، مایکروفون یا کمره وګورئ', 'fa': 'تماس برقرار نشد. اینترنت، میکروفون یا دوربین را بررسی کنید', 'en': 'Call failed. Check internet, microphone or camera'},
    'call_busy': {'ps': 'تاسو اوس په بل زنګ کې یاست', 'fa': 'شما در تماس دیگری هستید', 'en': 'You are already in a call'},
    'no_calls': {'ps': 'تر اوسه زنګ نشته', 'fa': 'هنوز تماسی نیست', 'en': 'No calls yet'},
    'no_calls_sub': {
      'ps': 'په یوه چټ کې د 📞 یا 📹 تڼۍ کېکاږئ.',
      'fa': 'در یک گفتگو دکمهٔ 📞 یا 📹 را بزنید.',
      'en': 'Open a chat and tap 📞 or 📹.',
    },
    'missed': {'ps': 'له لاسه وتلی', 'fa': 'از دست رفته', 'en': 'Missed'},
    'mute': {'ps': 'غږ بند', 'fa': 'بی‌صدا', 'en': 'Mute'},
    'camera': {'ps': 'کمره', 'fa': 'دوربین', 'en': 'Camera'},
    'flip': {'ps': 'کمره اړول', 'fa': 'چرخاندن دوربین', 'en': 'Flip'},
    'end_call': {'ps': 'بندول', 'fa': 'قطع', 'en': 'End'},
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
