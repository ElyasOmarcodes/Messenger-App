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

  static AppLang fromCode(String? code) => AppLang.values.firstWhere((l) => l.code == code, orElse: () => AppLang.ps);
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
    'err_network': {
      'ps': 'سرور ته نښلېدل ونه شول. انټرنېټ وګورئ',
      'fa': 'اتصال به سرور ممکن نشد. اینترنت را بررسی کنید',
      'en': 'Could not reach the server. Check your internet',
    },
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
      'ps': 'د «نوی چټ» تڼۍ کېکاږئ او د ملګري ایمیل ولیکئ.',
      'fa': 'دکمهٔ «گفتگوی تازه» را بزنید و ایمیل دوست‌تان را بنویسید.',
      'en': "Tap “New chat” and enter a friend's email.",
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
    'say_hello': {'ps': 'سلام ووایاست', 'fa': 'سلام کنید', 'en': 'Say hello'},

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
    'profile': {'ps': 'پروفایل', 'fa': 'پروفایل', 'en': 'Profile'},
    'username': {'ps': 'کارن نوم', 'fa': 'نام کاربری', 'en': 'Username'},
    'username_hint': {'ps': 'یوازې انګلیسي توري، عدد او _ (۳ تر ۲۴)', 'fa': 'فقط حروف انگلیسی، عدد و _ (۳ تا ۲۴)', 'en': 'Letters a–z, digits and _ (3–24)'},
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
    'call_failed': {
      'ps': 'زنګ ونه شو. انټرنېټ، مایکروفون یا کمره وګورئ',
      'fa': 'تماس برقرار نشد. اینترنت، میکروفون یا دوربین را بررسی کنید',
      'en': 'Call failed. Check internet, microphone or camera',
    },
    'call_busy': {'ps': 'تاسو اوس په بل زنګ کې یاست', 'fa': 'شما در تماس دیگری هستید', 'en': 'You are already in a call'},
    'no_calls': {'ps': 'تر اوسه زنګ نشته', 'fa': 'هنوز تماسی نیست', 'en': 'No calls yet'},
    'no_calls_sub': {
      'ps': 'یو چټ پرانیزئ او د زنګ تڼۍ کېکاږئ.',
      'fa': 'یک گفتگو را باز کنید و دکمهٔ تماس را بزنید.',
      'en': 'Open a chat and tap the call button.',
    },
    'missed': {'ps': 'له لاسه وتلی', 'fa': 'از دست رفته', 'en': 'Missed'},
    'mute': {'ps': 'غږ بند', 'fa': 'بی‌صدا', 'en': 'Mute'},
    'camera': {'ps': 'کمره', 'fa': 'دوربین', 'en': 'Camera'},
    'flip': {'ps': 'کمره اړول', 'fa': 'چرخاندن دوربین', 'en': 'Flip'},
    'end_call': {'ps': 'بندول', 'fa': 'قطع', 'en': 'End'},
    'continue': {'ps': 'دوام', 'fa': 'ادامه', 'en': 'Continue'},
    'notifications': {'ps': 'خبرتیاوې', 'fa': 'اعلان‌ها', 'en': 'Notifications'},
    'notifications_body': {
      'ps': 'کله چې اپ خلاص یا شاته وي، د نویو پیغامونو او زنګونو خبرتیا درځي. د بشپړ تړل شوي اپ لپاره خبرتیاوې (Push) د Firebase حساب سره فعالېږي.',
      'fa': 'وقتی برنامه باز یا در پس‌زمینه است، برای پیام و تماس تازه اعلان می‌آید. اعلان برای برنامهٔ کاملاً بسته با حساب Firebase فعال می‌شود.',
      'en': 'You get notifications for new messages and calls while the app is open or in the background. Push for a fully closed app is enabled with a Firebase account.',
    },
    // ── v0.4: Telegram-style screens ──────────────────────────────────────
    'start_messaging': {'ps': 'خبرې پیل کړئ', 'fa': 'شروع گفتگو', 'en': 'Start Messaging'},
    'welcome_points': {
      'ps': 'ګړندي پیغامونه، انځورونه، غږیز پیغامونه او زنګونه.\nپه پښتو، دری او انګلیسي.',
      'fa': 'پیام سریع، عکس، پیام صوتی و تماس.\nبه پشتو، دری و انگلیسی.',
      'en': 'Fast messages, photos, voice notes and calls.\nIn Pashto, Dari and English.',
    },
    'your_email': {'ps': 'ستاسو ایمیل', 'fa': 'ایمیل شما', 'en': 'Your email'},
    'your_email_sub': {
      'ps': 'خپل ایمیل ولیکئ. که حساب نه لرئ، نوی به جوړ شي.',
      'fa': 'ایمیل خود را بنویسید. اگر حساب ندارید، ساخته می‌شود.',
      'en': "Enter your email. If you don't have an account, we'll create one.",
    },
    'enter_password': {'ps': 'پټنوم ولیکئ', 'fa': 'رمز را بنویسید', 'en': 'Enter your password'},
    'enter_password_sub': {'ps': 'د {email} حساب', 'fa': 'حساب {email}', 'en': 'Account {email}'},
    'your_info': {'ps': 'ستاسو معلومات', 'fa': 'اطلاعات شما', 'en': 'Your info'},
    'your_info_sub': {
      'ps': 'نوم او پټنوم ولیکئ. نوم مو ملګري ویني.',
      'fa': 'نام و رمز را بنویسید. دوستان نام شما را می‌بینند.',
      'en': 'Enter your name and a password. Friends will see your name.',
    },
    'check_email': {'ps': 'خپل ایمیل وګورئ', 'fa': 'ایمیل خود را ببینید', 'en': 'Check your email'},
    'resend_in': {'ps': 'کوډ بیا ولېږئ ({s})', 'fa': 'ارسال دوباره ({s})', 'en': 'Resend code ({s})'},
    'change_email': {'ps': 'ایمیل بدل کړئ', 'fa': 'تغییر ایمیل', 'en': 'Change email'},
    'contacts': {'ps': 'اړیکې', 'fa': 'مخاطبین', 'en': 'Contacts'},
    'profile_tab': {'ps': 'پروفایل', 'fa': 'پروفایل', 'en': 'Profile'},
    'all': {'ps': 'ټول', 'fa': 'همه', 'en': 'All'},
    'personal': {'ps': 'شخصي', 'fa': 'شخصی', 'en': 'Personal'},
    'groups': {'ps': 'ډلې', 'fa': 'گروه‌ها', 'en': 'Groups'},
    'unread': {'ps': 'نالوستي', 'fa': 'خوانده‌نشده', 'en': 'Unread'},
    'add_contact': {'ps': 'نوې اړیکه', 'fa': 'مخاطب تازه', 'en': 'Add contact'},
    'contacts_empty': {
      'ps': 'هغه کسان چې ورسره خبرې کوئ دلته ښکاري.',
      'fa': 'کسانی که با آن‌ها گفتگو می‌کنید این‌جا دیده می‌شوند.',
      'en': 'People you chat with appear here.',
    },
    'info': {'ps': 'معلومات', 'fa': 'اطلاعات', 'en': 'Info'},
    'media': {'ps': 'انځورونه', 'fa': 'عکس‌ها', 'en': 'Media'},
    'files': {'ps': 'فایلونه', 'fa': 'فایل‌ها', 'en': 'Files'},
    'message': {'ps': 'پیغام', 'fa': 'پیام', 'en': 'Message'},
    'no_media': {'ps': 'تر اوسه هېڅ نشته', 'fa': 'هنوز چیزی نیست', 'en': 'Nothing here yet'},
    'group_info': {'ps': 'د ډلې معلومات', 'fa': 'اطلاعات گروه', 'en': 'Group info'},
    'admin': {'ps': 'مدیر', 'fa': 'مدیر', 'en': 'admin'},
    'night_mode': {'ps': 'شپې بڼه', 'fa': 'حالت شب', 'en': 'Night mode'},
    'appearance_sub': {'ps': 'رنګ او بڼه', 'fa': 'رنگ و نما', 'en': 'Colours and theme'},
    'account': {'ps': 'حساب', 'fa': 'حساب', 'en': 'Account'},
    'online_now': {'ps': 'وصل', 'fa': 'آنلاین', 'en': 'online'},
    'tap_profile': {'ps': 'د معلوماتو لپاره کېکاږئ', 'fa': 'برای اطلاعات بزنید', 'en': 'tap for info'},
    // v0.6: saved messages, chat options
    // v0.10: end-to-end encryption
    'locked_message': {'ps': 'پټ پیغام (کیلي نشته)', 'fa': 'پیام رمزگذاری‌شده (کلید نیست)', 'en': 'Encrypted message (no key)'},
    'wrong_pin': {'ps': 'PIN سم نه دی', 'fa': 'PIN درست نیست', 'en': 'Wrong PIN'},
    'e2e_title': {'ps': 'د پای تر پایه کوډ کول', 'fa': 'رمزگذاری سرتاسری', 'en': 'End-to-end encryption'},
    'e2e_create_title': {'ps': 'د پیغامونو PIN جوړ کړئ', 'fa': 'PIN پیام‌ها را بسازید', 'en': 'Create your message PIN'},
    'e2e_create_body': {
      'ps': 'ستاسو پیغامونه، انځورونه او فایلونه یوازې ستاسو او د مخاطب په تلیفون کې پرانیستل کېږي. دا PIN ستاسو کیلي قلفوي، څو په نوي تلیفون کې زاړه پیغامونه بېرته راوړئ. PIN هېڅکله سرور ته نه ځي.',
      'fa': 'پیام‌ها، عکس‌ها و فایل‌های شما فقط روی گوشی شما و مخاطب باز می‌شوند. این PIN کلید شما را قفل می‌کند تا روی گوشی تازه پیام‌های قبلی را برگردانید. PIN هرگز به سرور نمی‌رود.',
      'en': 'Your messages, photos and files open only on your phone and the other person\'s. This PIN locks your key so you can bring old messages back on a new phone. The PIN never leaves your phone.',
    },
    'e2e_restore_title': {'ps': 'خپل PIN ولیکئ', 'fa': 'PIN خود را وارد کنید', 'en': 'Enter your PIN'},
    'e2e_restore_body': {
      'ps': 'دا حساب پخوا کوډ شوې کیلي لري. د پیغامونو د پرانیستلو لپاره هغه PIN ولیکئ چې مو جوړ کړی و.',
      'fa': 'این حساب کلید رمزشده دارد. برای باز کردن پیام‌ها PIN را که ساخته بودید وارد کنید.',
      'en': 'This account already has an encrypted key. Enter the PIN you created to open your messages.',
    },
    'pin_hint': {'ps': 'لږ تر لږه ۸ توري (توري او شمېرې ګډې)', 'fa': 'دست‌کم ۸ نویسه (حرف و رقم)', 'en': 'At least 8 characters (letters and digits)'},
    'pin_again': {'ps': 'PIN بیا ولیکئ', 'fa': 'PIN را دوباره وارد کنید', 'en': 'Enter the PIN again'},
    'pin_mismatch': {'ps': 'دواړه PIN یو شان نه دي', 'fa': 'دو PIN یکسان نیستند', 'en': 'The PINs do not match'},
    'pin_short': {'ps': 'PIN باید لږ تر لږه ۸ توري وي', 'fa': 'PIN باید دست‌کم ۸ نویسه باشد', 'en': 'The PIN must be at least 8 characters'},
    'pin_tip': {
      'ps': 'اوږد PIN (توري او شمېرې ګډې) تر ټولو خوندي دی.',
      'fa': 'PIN بلندتر (حرف و رقم) امن‌تر است.',
      'en': 'A longer PIN with letters and digits is safest.',
    },
    'pin_working': {'ps': 'کیلي جوړېږي…', 'fa': 'در حال ساخت کلید…', 'en': 'Making your key…'},
    'pin_forgot': {'ps': 'PIN مې هېر دی', 'fa': 'PIN را فراموش کرده‌ام', 'en': 'I forgot my PIN'},
    'pin_forgot_q': {
      'ps': 'نوې کیلي جوړېږي. هغه پیغامونه چې پخوا د زړې کیلي سره کوډ شوي، ښايي بیا پرانیستل نه شي. دوام ورکوئ؟',
      'fa': 'کلید تازه ساخته می‌شود. پیام‌هایی که با کلید قبلی رمز شده‌اند شاید دیگر باز نشوند. ادامه می‌دهید؟',
      'en': 'A new key will be made. Messages encrypted with the old key may no longer open. Continue?',
    },
    'e2e_offline': {'ps': 'د کیلي د چک لپاره انټرنېټ ته اړتیا ده', 'fa': 'برای بررسی کلید به اینترنت نیاز است', 'en': 'Internet is needed to check your key'},
    'pin_weak': {
      'ps': 'دا PIN کمزوری دی. توري او شمېرې ګډې کړئ (یا ۱۲+ توري) او عام PIN مه کاروئ.',
      'fa': 'این PIN ضعیف است. حرف و رقم را ترکیب کنید (یا ۱۲+ نویسه) و از PIN رایج استفاده نکنید.',
      'en': 'This PIN is weak. Mix letters and digits (or use 12+ characters) and avoid common ones.',
    },
    'pin_strengthen_title': {'ps': 'قوي PIN جوړ کړئ', 'fa': 'PIN قوی بسازید', 'en': 'Make a stronger PIN'},
    'pin_strengthen_body': {
      'ps': 'ستاسو پخوانی PIN لنډ دی. که څوک سرور هک هم کړي، باید ستاسو کیلي پرانیستل ناشوني وي؛ نو یو قوي PIN وټاکئ.',
      'fa': 'PIN قبلی شما کوتاه است. حتی اگر کسی سرور را هک کند، باز کردن کلید شما باید ناممکن باشد؛ پس PIN قوی انتخاب کنید.',
      'en': 'Your old PIN is short. Even if someone breaks into the server, your key must stay impossible to open, so choose a strong PIN.',
    },
    'key_changed': {
      'ps': 'د {name} د کوډ کیلي بدله شوې. تر هغو چې یې تایید نه کړئ، نوي پیغامونه ورته نه کوډ کېږي.',
      'fa': 'کلید رمزگذاری {name} تغییر کرده. تا تأیید نکنید، پیام تازه برایش رمز نمی‌شود.',
      'en': '{name}\'s encryption key changed. New messages are not encrypted for them until you confirm.',
    },
    'verify_key': {'ps': 'تایید وګورئ', 'fa': 'بررسی', 'en': 'Verify'},
    'accept_key': {'ps': 'منل', 'fa': 'پذیرفتن', 'en': 'Accept'},
    'retry': {'ps': 'بیا هڅه', 'fa': 'تلاش دوباره', 'en': 'Try again'},
    'safety_number': {'ps': 'د خوندیتوب شمېره', 'fa': 'شماره امنیتی', 'en': 'Safety number'},
    'safety_body': {
      'ps': 'دا شمېره د خپل مخاطب له تلیفون سره پرتله کړئ. که یو شان وي، ستاسو خبرې پای تر پایه کوډ دي او څوک په منځ کې نشته.',
      'fa': 'این شماره را با گوشی مخاطب مقایسه کنید. اگر یکسان باشد، گفتگو سرتاسری رمز است و کسی در میان نیست.',
      'en': 'Compare this number with the other person\'s phone. If it matches, your chat is end-to-end encrypted with no one in between.',
    },
    'change_pin': {'ps': 'د پیغامونو PIN بدلول', 'fa': 'تغییر PIN پیام‌ها', 'en': 'Change message PIN'},
    'pin_changed': {'ps': 'PIN بدل شو', 'fa': 'PIN تغییر کرد', 'en': 'PIN changed'},
    'e2e_chat_note': {'ps': 'پیغامونه پای تر پایه کوډ شوي دي', 'fa': 'پیام‌ها سرتاسری رمز شده‌اند', 'en': 'Messages are end-to-end encrypted'},
    // v0.9: photo viewer, outbox, downloads
    'more': {'ps': 'نور', 'fa': 'بیشتر', 'en': 'More'},
    'share': {'ps': 'شریکول', 'fa': 'اشتراک‌گذاری', 'en': 'Share'},
    'save_gallery': {'ps': 'ګالرۍ ته خوندي کول', 'fa': 'ذخیره در گالری', 'en': 'Save to Gallery'},
    'saved_gallery': {'ps': 'ګالرۍ ته خوندي شو', 'fa': 'در گالری ذخیره شد', 'en': 'Saved to Gallery'},
    'show_all_media': {'ps': 'ټولې رسنۍ ښودل', 'fa': 'نمایش همهٔ رسانه‌ها', 'en': 'Show All Media'},
    'show_in_chat': {'ps': 'په چټ کې ښودل', 'fa': 'نمایش در گفتگو', 'en': 'Show in Chat'},
    'n_of_m': {'ps': '{a} له {b}', 'fa': '{a} از {b}', 'en': '{a} of {b}'},
    'day_at': {'ps': '{d} په {t}', 'fa': '{d} ساعت {t}', 'en': '{d} at {t}'},
    'draw': {'ps': 'انځور کښل', 'fa': 'نقاشی', 'en': 'Draw'},
    'waiting_network': {'ps': 'د انټرنېټ په تمه…', 'fa': 'در انتظار شبکه…', 'en': 'Waiting for network…'},
    'cancel_download': {'ps': 'ښکته کول بندول', 'fa': 'لغو دانلود', 'en': 'Cancel download'},
    'downloading': {'ps': 'ښکته کېږي…', 'fa': 'در حال دانلود…', 'en': 'Downloading…'},
    'stories_cache': {'ps': 'کیسې', 'fa': 'استوری‌ها', 'en': 'Stories'},
    'data_storage': {'ps': 'معلومات او زېرمه', 'fa': 'داده‌ها و ذخیره‌سازی', 'en': 'Data and storage'},
    'data_storage_sub': {'ps': 'د حافظې کارول، د رسنیو ساتنه', 'fa': 'مصرف حافظه، نگهداری رسانه', 'en': 'Storage usage, keep media'},
    'cache_used': {'ps': 'په مبایل کې کارول شوې حافظه', 'fa': 'حافظهٔ استفاده‌شده روی گوشی', 'en': 'Used on this device'},
    'cache_note': {
      'ps': 'ټول شیان په سرور کې خوندي دي. پاکول یوازې د مبایل ځای خالي کوي؛ چې بیا یې خلاص کړئ، بېرته ښکته کېږي.',
      'fa': 'همه‌چیز روی سرور محفوظ است. پاک کردن فقط جای گوشی را آزاد می‌کند؛ با باز کردن دوباره دانلود می‌شود.',
      'en': 'Everything stays on the server. Clearing only frees space here; files download again when opened.',
    },
    'cache_note_web': {'ps': 'په براوزر کې فایلونه نه ساتل کېږي.', 'fa': 'در مرورگر فایل‌ها نگه‌داری نمی‌شوند.', 'en': 'The browser does not keep files.'},
    'clear_cache': {'ps': 'حافظه پاکول', 'fa': 'پاک کردن حافظه', 'en': 'Clear cache'},
    'clear_cache_q': {
      'ps': 'دا فایلونه له مبایله پاک شي؟ په سرور کې پاتې کېږي.',
      'fa': 'این فایل‌ها از گوشی پاک شوند؟ روی سرور می‌مانند.',
      'en': 'Remove these files from this device? They stay on the server.',
    },
    'keep_media': {'ps': 'رسنۍ وساتئ', 'fa': 'نگهداری رسانه', 'en': 'Keep media'},
    'keep_media_sub': {
      'ps': 'هغه فایلونه چې دومره موده نه وي خلاص شوي، پاکېږي',
      'fa': 'فایل‌هایی که این مدت باز نشده‌اند پاک می‌شوند',
      'en': 'Files not opened for this long are removed',
    },
    'keep_3d': {'ps': '۳ ورځې', 'fa': '۳ روز', 'en': '3 days'},
    'keep_1w': {'ps': 'یوه اوونۍ', 'fa': 'یک هفته', 'en': '1 week'},
    'keep_1m': {'ps': 'یوه میاشت', 'fa': 'یک ماه', 'en': '1 month'},
    'keep_forever': {'ps': 'تل', 'fa': 'همیشه', 'en': 'Forever'},
    'max_cache': {'ps': 'د حافظې حد', 'fa': 'حداکثر حافظه', 'en': 'Max cache size'},
    'no_limit': {'ps': 'بې حده', 'fa': 'بدون محدودیت', 'en': 'No limit'},
    'auto_photos': {'ps': 'انځورونه پخپله ښکته شي', 'fa': 'دانلود خودکار عکس‌ها', 'en': 'Auto-download photos'},
    'auto_photos_sub': {
      'ps': 'که بند وي، انځور په ګوته وهلو ښکته کېږي',
      'fa': 'اگر خاموش باشد، با لمس دانلود می‌شود',
      'en': 'When off, tap a photo to download it',
    },
    'by_chat': {'ps': 'د چټونو له مخې', 'fa': 'بر اساس گفتگو', 'en': 'By chat'},
    'profile_photos': {'ps': 'د پروفایل انځورونه', 'fa': 'عکس‌های پروفایل', 'en': 'Profile photos'},
    'other_media': {'ps': 'نورې رسنۍ', 'fa': 'رسانه‌های دیگر', 'en': 'Other media'},
    'cache_empty': {'ps': 'حافظه تشه ده', 'fa': 'حافظه خالی است', 'en': 'Nothing stored yet'},
    'chat_settings': {'ps': 'د چټ ترتیبات', 'fa': 'تنظیمات گفتگو', 'en': 'Chat settings'},
    'chat_settings_sub': {'ps': 'شپې بڼه، رنګ، ښیښه‌یي بڼه', 'fa': 'حالت شب، رنگ، جلوهٔ شیشه‌ای', 'en': 'Night mode, theme, glass'},
    'account_sub': {'ps': 'ایمیل، کارن‌نوم، انځور', 'fa': 'ایمیل، نام کاربری، عکس', 'en': 'Email, username, photo'},
    'privacy_sub': {'ps': 'څوک مو لیدلی شي، امنیت', 'fa': 'چه کسی شما را می‌بیند، امنیت', 'en': 'Who can see you, security'},
    'notifications_sub': {'ps': 'غږونه، زنګونه، نښې', 'fa': 'صداها، تماس‌ها، نشان‌ها', 'en': 'Sounds, calls, badges'},
    'saved_sub': {'ps': 'ستاسو شخصي زېرمه', 'fa': 'فضای شخصی شما', 'en': 'Your personal storage'},
    'my_qr': {'ps': 'زما QR کوډ', 'fa': 'کد QR من', 'en': 'My QR code'},
    'like_story': {'ps': 'زړه ورکول', 'fa': 'پسندیدن', 'en': 'Like'},
    'links': {'ps': 'لینکونه', 'fa': 'لینک‌ها', 'en': 'Links'},
    'back': {'ps': 'شاته', 'fa': 'بازگشت', 'en': 'Back'},
    'glass_effect': {'ps': 'ښیښه‌یي بڼه', 'fa': 'جلوهٔ شیشه‌ای', 'en': 'Glass effect'},
    'glass_effect_sub': {'ps': 'په ورو مبایلونو کې یې بند کړئ', 'fa': 'در گوشی‌های کند خاموش کنید', 'en': 'Turn off on slow phones'},
    'story_label': {'ps': 'کیسه', 'fa': 'استوری', 'en': 'Story'},
    'download': {'ps': 'ښکته کول', 'fa': 'دانلود', 'en': 'Download'},
    'saved_messages': {'ps': 'خوندي پیغامونه', 'fa': 'پیام‌های ذخیره‌شده', 'en': 'Saved Messages'},
    'saved_short': {'ps': 'خوندي', 'fa': 'ذخیره‌ها', 'en': 'Saved'},
    'saved_hint': {
      'ps': 'دلته پیغامونه، انځورونه او فایلونه ځانته خوندي کړئ. یوازې تاسو یې لیدلی شئ.',
      'fa': 'پیام‌ها، عکس‌ها و فایل‌ها را اینجا برای خود نگه دارید. فقط شما آن‌ها را می‌بینید.',
      'en': 'Keep messages, photos and files for yourself here. Only you can see them.',
    },
    'saved_hint_short': {'ps': 'ستاسو شخصي زېرمه', 'fa': 'فضای شخصی شما', 'en': 'Your personal storage'},
    'saved_toast': {'ps': 'په خوندي پیغامونو کې کېښودل شو', 'fa': 'در پیام‌های ذخیره‌شده گذاشته شد', 'en': 'Added to Saved Messages'},
    'save_message': {'ps': 'خوندي کول', 'fa': 'ذخیره', 'en': 'Save'},
    'pin_chat': {'ps': 'پورته نښلول', 'fa': 'سنجاق کردن', 'en': 'Pin'},
    'unpin_chat': {'ps': 'له پورته لرې کول', 'fa': 'برداشتن سنجاق', 'en': 'Unpin'},
    'pin_limit': {'ps': 'تر ۵ چټونو زیات نه شي نښلول کېدای', 'fa': 'بیش از ۵ گفتگو سنجاق نمی‌شود', 'en': 'You can pin up to 5 chats'},
    'mute_chat': {'ps': 'خبرتیاوې بندول', 'fa': 'خاموش کردن اعلان‌ها', 'en': 'Mute'},
    'unmute_chat': {'ps': 'خبرتیاوې پرانیستل', 'fa': 'روشن کردن اعلان‌ها', 'en': 'Unmute'},
    'muted_toast': {'ps': 'خبرتیاوې بندې شوې', 'fa': 'اعلان‌ها خاموش شد', 'en': 'Notifications muted'},
    'unmuted_toast': {'ps': 'خبرتیاوې پرانیستل شوې', 'fa': 'اعلان‌ها روشن شد', 'en': 'Notifications on'},
    'mark_read': {'ps': 'لوستل شوی په نښه کړئ', 'fa': 'علامت خوانده‌شده', 'en': 'Mark as read'},
    'mark_unread': {'ps': 'نالوستی په نښه کړئ', 'fa': 'علامت خوانده‌نشده', 'en': 'Mark as unread'},
    'archive': {'ps': 'آرشیف', 'fa': 'بایگانی', 'en': 'Archive'},
    'unarchive': {'ps': 'له آرشیفه راایستل', 'fa': 'خروج از بایگانی', 'en': 'Unarchive'},
    'chat_archived': {'ps': 'چټ آرشیف ته ولاړ', 'fa': 'گفتگو بایگانی شد', 'en': 'Chat archived'},
    'undo': {'ps': 'بېرته', 'fa': 'برگرداندن', 'en': 'Undo'},
    'archived_chats': {'ps': 'آرشیف شوي چټونه', 'fa': 'گفتگوهای بایگانی‌شده', 'en': 'Archived chats'},
    'archive_empty': {'ps': 'آرشیف تش دی', 'fa': 'بایگانی خالی است', 'en': 'No archived chats'},
    'archive_hint': {
      'ps': 'چې غږ یې بند نه وي، نوی پیغام یې بېرته لیست ته راولي.',
      'fa': 'اگر بی‌صدا نباشد، پیام تازه آن را به فهرست برمی‌گرداند.',
      'en': 'A new message brings a chat back unless it is muted.',
    },
    'clear_history': {'ps': 'تاریخچه پاکول', 'fa': 'پاک کردن تاریخچه', 'en': 'Clear history'},
    'clear_history_q': {'ps': 'ټول پیغامونه یوازې ستاسو لپاره پاک شي؟', 'fa': 'همه پیام‌ها فقط برای شما پاک شود؟', 'en': 'Clear all messages for you?'},
    'clear': {'ps': 'پاکول', 'fa': 'پاک کردن', 'en': 'Clear'},
    'history_cleared': {'ps': 'تاریخچه پاکه شوه', 'fa': 'تاریخچه پاک شد', 'en': 'History cleared'},
    'delete_chat': {'ps': 'چټ ړنګول', 'fa': 'حذف گفتگو', 'en': 'Delete chat'},
    'delete_chat_q': {'ps': 'دا چټ ستاسو له لیسته ړنګ شي؟', 'fa': 'این گفتگو از فهرست شما حذف شود؟', 'en': 'Delete this chat from your list?'},
    // v0.5: chat, stories
    'camera_failed': {'ps': 'کمره پرانیستل نه شوه', 'fa': 'کمره باز نشد', 'en': 'Could not open the camera'},
    'location_denied': {'ps': 'د ځای اجازه ورنه کړل شوه', 'fa': 'اجازهٔ موقعیت داده نشد', 'en': 'Location permission denied'},
    'locating': {'ps': 'ستاسو ځای موندل کېږي…', 'fa': 'در حال یافتن موقعیت شما…', 'en': 'Finding your location…'},
    'location_failed': {'ps': 'ځای ونه موندل شو', 'fa': 'موقعیت یافت نشد', 'en': 'Could not get your location'},
    'share_contact': {'ps': 'اړیکه ولېږئ', 'fa': 'فرستادن مخاطب', 'en': 'Share a contact'},
    'phone_contact': {'ps': 'یا شمېره ولیکئ', 'fa': 'یا شماره را بنویسید', 'en': 'Or type a number'},
    'contact_name': {'ps': 'نوم', 'fa': 'نام', 'en': 'Name'},
    'phone_number': {'ps': 'د تلیفون شمېره', 'fa': 'شمارهٔ تلفن', 'en': 'Phone number'},
    'send': {'ps': 'لېږل', 'fa': 'فرستادن', 'en': 'Send'},
    'gallery': {'ps': 'ګالري', 'fa': 'گالری', 'en': 'Gallery'},
    'location': {'ps': 'ځای', 'fa': 'موقعیت', 'en': 'Location'},
    'contact': {'ps': 'اړیکه', 'fa': 'مخاطب', 'en': 'Contact'},
    'hold_to_record': {'ps': 'د غږ ثبتولو لپاره ګوته ونیسئ', 'fa': 'برای ضبط صدا نگه دارید', 'en': 'Hold to record, release to send'},
    'pinned': {'ps': 'پیغام پورته ونښلول شو', 'fa': 'پیام سنجاق شد', 'en': 'Message pinned'},
    'unpinned': {'ps': 'پیغام له پورته لرې شو', 'fa': 'سنجاق برداشته شد', 'en': 'Message unpinned'},
    'forwarded': {'ps': 'پیغام ولېږل شو', 'fa': 'پیام هدایت شد', 'en': 'Message forwarded'},
    'delete_message': {'ps': 'پیغام ړنګول', 'fa': 'حذف پیام', 'en': 'Delete message'},
    'forward_to': {'ps': 'چاته یې ولېږم؟', 'fa': 'به چه کسی بفرستم؟', 'en': 'Forward to…'},
    'pinned_message': {'ps': 'نښلول شوی پیغام', 'fa': 'پیام سنجاق‌شده', 'en': 'Pinned message'},
    'pin': {'ps': 'پورته نښلول', 'fa': 'سنجاق کردن', 'en': 'Pin'},
    'unpin': {'ps': 'له پورته لرې کول', 'fa': 'برداشتن سنجاق', 'en': 'Unpin'},
    'no_recent_emoji': {'ps': 'تر اوسه هېڅ نشته', 'fa': 'هنوز چیزی نیست', 'en': 'No recents yet'},
    'keyboard': {'ps': 'کیبورډ', 'fa': 'صفحه‌کلید', 'en': 'Keyboard'},
    'emoji': {'ps': 'ایموجي', 'fa': 'ایموجی', 'en': 'Emoji'},
    'attach': {'ps': 'ضمیمه', 'fa': 'پیوست', 'en': 'Attach'},
    'slide_cancel': {'ps': 'د لغوه کولو لپاره کش کړئ', 'fa': 'برای لغو بکشید', 'en': 'Slide to cancel'},
    'edit_message': {'ps': 'پیغام سمول', 'fa': 'ویرایش پیام', 'en': 'Edit message'},
    'edit': {'ps': 'سمول', 'fa': 'ویرایش', 'en': 'Edit'},
    'edited': {'ps': 'سم شوی', 'fa': 'ویرایش‌شده', 'en': 'edited'},
    'forward': {'ps': 'بل چاته لېږل', 'fa': 'هدایت', 'en': 'Forward'},
    'album_n': {'ps': '{n} انځوره', 'fa': '{n} عکس', 'en': '{n} photos'},
    'call_number': {'ps': 'زنګ', 'fa': 'تماس', 'en': 'Call'},
    'stories': {'ps': 'کیسې', 'fa': 'استوری‌ها', 'en': 'Stories'},
    'my_story': {'ps': 'زما کیسه', 'fa': 'استوری من', 'en': 'My story'},
    'add_story': {'ps': 'نوې کیسه', 'fa': 'استوری تازه', 'en': 'New story'},
    'expires_24h': {'ps': '۲۴ ساعته', 'fa': '۲۴ ساعت', 'en': '24 hours'},
    'text_story': {'ps': 'متن', 'fa': 'متن', 'en': 'Text'},
    'story_posted': {'ps': 'کیسه مو خپره شوه', 'fa': 'استوری شما منتشر شد', 'en': 'Your story is live'},
    'story_text_hint': {'ps': 'څه ولیکئ…', 'fa': 'چیزی بنویسید…', 'en': 'Type something…'},
    'add_caption': {'ps': 'یوه لیکنه ورزیاته کړئ…', 'fa': 'نوشته‌ای اضافه کنید…', 'en': 'Add a caption…'},
    'post_story': {'ps': 'خپرول', 'fa': 'انتشار', 'en': 'Post'},
    'reply_sent': {'ps': 'ځواب مو ولېږل شو', 'fa': 'پاسخ شما فرستاده شد', 'en': 'Reply sent'},
    'story_viewers': {'ps': 'کتونکي', 'fa': 'بینندگان', 'en': 'Viewers'},
    'views': {'ps': 'کتنې', 'fa': 'بازدید', 'en': 'views'},
    'no_views': {'ps': 'تر اوسه چا نه ده لیدلې', 'fa': 'هنوز کسی ندیده است', 'en': 'No views yet'},
    'delete_story': {'ps': 'کیسه ړنګول', 'fa': 'حذف استوری', 'en': 'Delete story'},
    'delete_story_q': {'ps': 'دا کیسه ړنګه شي؟', 'fa': 'این استوری حذف شود؟', 'en': 'Delete this story?'},
    'reply_story': {'ps': 'ځواب ورکړئ…', 'fa': 'پاسخ دهید…', 'en': 'Reply…'},
    'close': {'ps': 'بندول', 'fa': 'بستن', 'en': 'Close'},
    'just_now': {'ps': 'همدا اوس', 'fa': 'همین حالا', 'en': 'just now'},
    'min_ago': {'ps': '{n} دقیقې مخکې', 'fa': '{n} دقیقه پیش', 'en': '{n} min ago'},
    'hours_ago': {'ps': '{n} ساعته مخکې', 'fa': '{n} ساعت پیش', 'en': '{n} h ago'},
  };
}

/// Holds the active language for the widget tree.
class LangScope extends InheritedWidget {
  const LangScope({super.key, required this.lang, required super.child});
  final AppLang lang;

  static AppLang of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LangScope>()?.lang ?? AppLang.ps;

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
