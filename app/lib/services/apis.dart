import 'dart:convert';

import 'package:http/http.dart' as http;

import '../l10n/strings.dart';

/// Free, key-less public APIs (most from github.com/public-apis/public-apis).
/// Each one is wrapped so it can be swapped for our own backend later.

class City {
  const City(this.key, this.ps, this.fa, this.en, this.lat, this.lon);
  final String key;
  final String ps, fa, en;
  final double lat, lon;

  String name(AppLang l) => switch (l) { AppLang.ps => ps, AppLang.fa => fa, AppLang.en => en };
}

const afghanCities = <City>[
  City('kabul', 'کابل', 'کابل', 'Kabul', 34.5553, 69.2075),
  City('kandahar', 'کندهار', 'قندهار', 'Kandahar', 31.6289, 65.7372),
  City('herat', 'هرات', 'هرات', 'Herat', 34.3529, 62.2040),
  City('mazar', 'مزارشریف', 'مزارشریف', 'Mazar-i-Sharif', 36.7090, 67.1109),
  City('jalalabad', 'جلال اباد', 'جلال‌آباد', 'Jalalabad', 34.4415, 70.4361),
  City('kunduz', 'کندز', 'کندز', 'Kunduz', 36.7280, 68.8680),
  City('ghazni', 'غزني', 'غزنی', 'Ghazni', 33.5536, 68.4269),
  City('khost', 'خوست', 'خوست', 'Khost', 33.3395, 69.9204),
  City('bamyan', 'بامیان', 'بامیان', 'Bamyan', 34.8210, 67.8270),
  City('faizabad', 'فیض اباد', 'فیض‌آباد', 'Faizabad', 37.1166, 70.5800),
];

/// GET with up to three attempts: free public APIs sometimes refuse a burst.
Future<Map<String, dynamic>> _getJson(String url) async {
  Object? lastError;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      lastError = Exception('HTTP ${res.statusCode}');
    } catch (e) {
      lastError = e;
    }
  }
  throw lastError ?? Exception('request failed');
}

/// Local names Afghans use for common currencies.
String currencyName(String code, AppLang l) {
  const ps = {
    'USD': 'ډالر', 'EUR': 'یورو', 'GBP': 'پونډ', 'AED': 'درهم', 'SAR': 'سعودي ریال',
    'TRY': 'ترکي لیره', 'CNY': 'یوان', 'PKR': 'کلدار', 'INR': 'هندي روپۍ', 'IRR': 'ایراني ریال',
  };
  const fa = {
    'USD': 'دالر', 'EUR': 'یورو', 'GBP': 'پوند', 'AED': 'درهم', 'SAR': 'ریال سعودی',
    'TRY': 'لیرهٔ ترکیه', 'CNY': 'یوان', 'PKR': 'کلدار', 'INR': 'روپیهٔ هند', 'IRR': 'ریال ایران',
  };
  return switch (l) { AppLang.ps => ps[code] ?? code, AppLang.fa => fa[code] ?? code, AppLang.en => code };
}

// ── Weather: Open-Meteo (public-apis › Weather) ───────────────────────────
class DayForecast {
  DayForecast(this.date, this.code, this.max, this.min);
  final DateTime date;
  final int code;
  final double max, min;
}

class Weather {
  Weather({
    required this.temp,
    required this.feels,
    required this.code,
    required this.wind,
    required this.humidity,
    required this.days,
  });
  final double temp, feels, wind;
  final int code, humidity;
  final List<DayForecast> days;
}

Future<Weather> fetchWeather(City c) async {
  final j = await _getJson(
    'https://api.open-meteo.com/v1/forecast?latitude=${c.lat}&longitude=${c.lon}'
    '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m'
    '&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=Asia%2FKabul&forecast_days=5',
  );
  final cur = j['current'] as Map<String, dynamic>;
  final d = j['daily'] as Map<String, dynamic>;
  final times = (d['time'] as List).cast<String>();
  return Weather(
    temp: (cur['temperature_2m'] as num).toDouble(),
    feels: (cur['apparent_temperature'] as num).toDouble(),
    humidity: (cur['relative_humidity_2m'] as num).toInt(),
    code: (cur['weather_code'] as num).toInt(),
    wind: (cur['wind_speed_10m'] as num).toDouble(),
    days: [
      for (var i = 0; i < times.length; i++)
        DayForecast(
          DateTime.parse(times[i]),
          ((d['weather_code'] as List)[i] as num).toInt(),
          ((d['temperature_2m_max'] as List)[i] as num).toDouble(),
          ((d['temperature_2m_min'] as List)[i] as num).toDouble(),
        ),
    ],
  );
}

/// WMO weather code -> label key + icon name.
({String ps, String fa, String en, String icon}) weatherLabel(int code) {
  if (code == 0) return (ps: 'لمریز', fa: 'آفتابی', en: 'Sunny', icon: 'sun');
  if (code <= 2) return (ps: 'لږ ورېځ', fa: 'نیمه‌ابری', en: 'Partly cloudy', icon: 'partly');
  if (code == 3) return (ps: 'ورېځ', fa: 'ابری', en: 'Cloudy', icon: 'cloud');
  if (code == 45 || code == 48) return (ps: 'لړه', fa: 'مه', en: 'Fog', icon: 'fog');
  if (code >= 51 && code <= 67) return (ps: 'باران', fa: 'باران', en: 'Rain', icon: 'rain');
  if (code >= 71 && code <= 77) return (ps: 'واوره', fa: 'برف', en: 'Snow', icon: 'snow');
  if (code >= 80 && code <= 82) return (ps: 'ږلۍ', fa: 'رگبار', en: 'Showers', icon: 'rain');
  if (code == 85 || code == 86) return (ps: 'واوره', fa: 'برف', en: 'Snow showers', icon: 'snow');
  if (code >= 95) return (ps: 'تالنده', fa: 'رعد و برق', en: 'Thunderstorm', icon: 'storm');
  return (ps: 'ورېځ', fa: 'ابری', en: 'Cloudy', icon: 'cloud');
}

// ── Prayer times: AlAdhan (free, no key) ──────────────────────────────────
class PrayerTimes {
  PrayerTimes(this.times, this.hijriDay, this.hijriYear, this.monthEn, this.monthAr);
  final Map<String, String> times; // fajr, sunrise, dhuhr, asr, maghrib, isha
  final String hijriDay, hijriYear, monthEn, monthAr;

  /// Lunar Hijri date, e.g. "14 Jumada al-Akhirah 1448".
  String hijri(AppLang l) =>
      localDigits('${int.parse(hijriDay)} ${l == AppLang.en ? monthEn : monthAr} $hijriYear', l);
}

Future<PrayerTimes> fetchPrayerTimes(City c) async {
  final now = DateTime.now();
  final date = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
  // method=1: University of Islamic Sciences, Karachi (common in Afghanistan); school=1: Hanafi Asr.
  final j = await _getJson(
    'https://api.aladhan.com/v1/timings/$date?latitude=${c.lat}&longitude=${c.lon}&method=1&school=1',
  );
  final data = j['data'] as Map<String, dynamic>;
  final t = data['timings'] as Map<String, dynamic>;
  String clean(String k) => (t[k] as String).split(' ').first;
  final h = (data['date'] as Map<String, dynamic>)['hijri'] as Map<String, dynamic>;
  final month = h['month'] as Map<String, dynamic>;
  return PrayerTimes(
    {
      'fajr': clean('Fajr'),
      'sunrise': clean('Sunrise'),
      'dhuhr': clean('Dhuhr'),
      'asr': clean('Asr'),
      'maghrib': clean('Maghrib'),
      'isha': clean('Isha'),
    },
    h['day'] as String,
    h['year'] as String,
    month['en'] as String,
    month['ar'] as String,
  );
}

// ── Exchange rates: ExchangeRate-API open endpoint (public-apis › Currency) ─
class Rate {
  Rate(this.code, this.unit, this.afn);
  final String code;
  final int unit;
  final double afn; // how many AFN for [unit] of [code]
}

class Rates {
  Rates(this.list, this.updated);
  final List<Rate> list;
  final DateTime updated;
}

const _rateUnits = {
  'USD': 1,
  'EUR': 1,
  'GBP': 1,
  'AED': 1,
  'SAR': 1,
  'TRY': 1,
  'CNY': 1,
  'PKR': 1000,
  'INR': 1000,
  'IRR': 1000000,
};

Future<Rates> fetchRates() async {
  final j = await _getJson('https://open.er-api.com/v6/latest/USD');
  final r = (j['rates'] as Map<String, dynamic>).map((k, v) => MapEntry(k, (v as num).toDouble()));
  final afnPerUsd = r['AFN']!;
  return Rates(
    [
      for (final e in _rateUnits.entries)
        if (r[e.key] != null) Rate(e.key, e.value, afnPerUsd / r[e.key]! * e.value),
    ],
    DateTime.fromMillisecondsSinceEpoch(((j['time_last_update_unix'] as num).toInt()) * 1000),
  );
}

// ── Quran: AlQuran Cloud (public-apis › Books) ────────────────────────────
class Ayah {
  Ayah({required this.arabic, required this.translation, required this.surah, required this.number});
  final String arabic, translation, surah;
  final int number;
}

String _editionFor(AppLang l) => switch (l) {
      AppLang.ps => 'ps.abdulwali',
      AppLang.fa => 'fa.fooladvand',
      AppLang.en => 'en.sahih',
    };

/// Same verse for everyone on the same day.
int ayahOfTheDay([DateTime? d]) {
  final now = d ?? DateTime.now();
  final dayIndex = now.difference(DateTime(2024)).inDays;
  return (dayIndex * 2654435761) % 6236 + 1;
}

Future<Ayah> fetchAyah(AppLang lang, {int? number}) async {
  final n = number ?? ayahOfTheDay();
  final j = await _getJson('https://api.alquran.cloud/v1/ayah/$n/editions/quran-simple,${_editionFor(lang)}');
  final list = (j['data'] as List).cast<Map<String, dynamic>>();
  final surah = list.first['surah'] as Map<String, dynamic>;
  return Ayah(
    arabic: list[0]['text'] as String,
    translation: list[1]['text'] as String,
    surah: lang == AppLang.en ? surah['englishName'] as String : surah['name'] as String,
    number: (list.first['numberInSurah'] as num).toInt(),
  );
}
