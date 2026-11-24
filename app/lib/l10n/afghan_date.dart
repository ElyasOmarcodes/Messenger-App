import 'strings.dart';

/// Afghanistan's official civil calendar is the Solar Hijri calendar.
/// Month names differ between Pashto and Dari, so both are kept here.
class SolarHijri {
  const SolarHijri(this.year, this.month, this.day);
  final int year;
  final int month; // 1..12
  final int day;

  static const _gDaysBeforeMonth = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];

  factory SolarHijri.fromDate(DateTime date) {
    final gy = date.year, gm = date.month, gd = date.day;
    final gy2 = gm > 2 ? gy + 1 : gy;
    var days = 355666 +
        365 * gy +
        (gy2 + 3) ~/ 4 -
        (gy2 + 99) ~/ 100 +
        (gy2 + 399) ~/ 400 +
        gd +
        _gDaysBeforeMonth[gm - 1];
    var jy = -1595 + 33 * (days ~/ 12053);
    days %= 12053;
    jy += 4 * (days ~/ 1461);
    days %= 1461;
    if (days > 365) {
      jy += (days - 1) ~/ 365;
      days = (days - 1) % 365;
    }
    int jm, jd;
    if (days < 186) {
      jm = 1 + days ~/ 31;
      jd = 1 + days % 31;
    } else {
      jm = 7 + (days - 186) ~/ 30;
      jd = 1 + (days - 186) % 30;
    }
    return SolarHijri(jy, jm, jd);
  }

  static const _monthsPs = [
    'وری', 'غویی', 'غبرګولی', 'چنګاښ', 'زمری', 'وږی',
    'تله', 'لړم', 'لیندۍ', 'مرغومی', 'سلواغه', 'کب',
  ];
  static const _monthsFa = [
    'حمل', 'ثور', 'جوزا', 'سرطان', 'اسد', 'سنبله',
    'میزان', 'عقرب', 'قوس', 'جدی', 'دلو', 'حوت',
  ];
  static const _monthsEn = [
    'Hamal', 'Sawr', 'Jawza', 'Saratan', 'Asad', 'Sunbula',
    'Mizan', 'Aqrab', 'Qaws', 'Jadi', 'Dalw', 'Hut',
  ];

  String monthName(AppLang lang) => switch (lang) {
        AppLang.ps => _monthsPs[month - 1],
        AppLang.fa => _monthsFa[month - 1],
        AppLang.en => _monthsEn[month - 1],
      };

  String format(AppLang lang) => localDigits('$day ${monthName(lang)} $year', lang);
}

const _weekdaysPs = ['دوشنبه', 'سه شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
const _weekdaysFa = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];
const _weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String weekdayName(DateTime d, AppLang lang) => switch (lang) {
      AppLang.ps => _weekdaysPs[d.weekday - 1],
      AppLang.fa => _weekdaysFa[d.weekday - 1],
      AppLang.en => _weekdaysEn[d.weekday - 1],
    };

String two(int n) => n.toString().padLeft(2, '0');

String hhmm(DateTime d, AppLang lang) => localDigits('${two(d.hour)}:${two(d.minute)}', lang);

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "12:40" for today, "Yesterday", weekday within a week, else solar date.
String chatListTime(DateTime d, AppLang lang, Strings s) {
  final now = DateTime.now();
  if (sameDay(d, now)) return hhmm(d, lang);
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return s.get('yesterday');
  if (now.difference(d).inDays < 7) return weekdayName(d, lang);
  final sh = SolarHijri.fromDate(d);
  return localDigits('${sh.day} ${sh.monthName(lang)}', lang);
}

String dayHeader(DateTime d, AppLang lang, Strings s) {
  final now = DateTime.now();
  if (sameDay(d, now)) return s.get('today');
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return s.get('yesterday');
  final sep = lang == AppLang.en ? ', ' : '، ';
  return '${weekdayName(d, lang)}$sep${SolarHijri.fromDate(d).format(lang)}';
}
