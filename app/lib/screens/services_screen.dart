import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../services/apis.dart';

/// "Services" tab: small daily tools built on free public APIs.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  City _city = afghanCities.first;
  late Future<Weather> _weather;
  late Future<PrayerTimes> _prayer;
  late Future<Rates> _rates;
  Future<Ayah>? _ayah;
  AppLang? _ayahLang;

  @override
  void initState() {
    super.initState();
    _loadCity();
    _rates = fetchRates();
  }

  void _loadCity() {
    _weather = fetchWeather(_city);
    _prayer = fetchPrayerTimes(_city);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l = context.lang;
    if (_ayahLang != l) {
      _ayahLang = l;
      _ayah = fetchAyah(l);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _loadCity();
          _rates = fetchRates();
          _ayah = fetchAyah(lang);
        });
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          _DateCard(prayer: _prayer),
          const SizedBox(height: 12),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: afghanCities.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = afghanCities[i];
                return ChoiceChip(
                  label: Text(c.name(lang)),
                  selected: c == _city,
                  showCheckmark: false,
                  onSelected: (_) => setState(() {
                    _city = c;
                    _loadCity();
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _WeatherCard(future: _weather, city: _city, onRetry: () => setState(() => _weather = fetchWeather(_city))),
          const SizedBox(height: 12),
          _PrayerCard(future: _prayer, city: _city, onRetry: () => setState(() => _prayer = fetchPrayerTimes(_city))),
          const SizedBox(height: 12),
          _RatesCard(future: _rates, onRetry: () => setState(() => _rates = fetchRates())),
          const SizedBox(height: 12),
          if (_ayah != null) _AyahCard(future: _ayah!, onRetry: () => setState(() => _ayah = fetchAyah(lang))),
        ],
      ),
    );
  }
}

// ── Shared pieces ─────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, this.trailing, required this.child, this.color});
  final IconData icon;
  final String title;
  final String? trailing;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: (color ?? cs.primary).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: color ?? cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800))),
                if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _Async<T> extends StatelessWidget {
  const _Async({required this.future, required this.builder, this.onRetry});
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.hasData) return builder(snap.data as T);
        if (snap.hasError) {
          return Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: Brand.pomegranate, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(context.tr('load_failed'))),
              if (onRetry != null)
                TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded, size: 18), label: Text(context.tr('retry'))),
            ],
          );
        }
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
        );
      },
    );
  }
}

// ── Today's date in three calendars ──────────────────────────────────────
class _DateCard extends StatelessWidget {
  const _DateCard({required this.prayer});
  final Future<PrayerTimes> prayer;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final now = DateTime.now();
    final sh = SolarHijri.fromDate(now);
    final greg = localDigits('${now.year}/${two(now.month)}/${two(now.day)}', lang);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.lapisBright, Brand.lapis, Brand.lapisDeep],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(weekdayName(now, lang), style: const TextStyle(color: Brand.saffron, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  sh.format(lang),
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.25),
                ),
                const SizedBox(height: 6),
                FutureBuilder<PrayerTimes>(
                  future: prayer,
                  builder: (_, s) => Text(
                    s.hasData ? '${s.data!.hijri(lang)}  ·  $greg' : greg,
                    style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13.5),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(color: Color(0x26FFFFFF), shape: BoxShape.circle),
            child: Center(
              child: Text(
                localDigits('${sh.day}', lang),
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Weather ───────────────────────────────────────────────────────────────
IconData _weatherIcon(String key) => switch (key) {
      'sun' => Icons.wb_sunny_rounded,
      'partly' => Icons.wb_cloudy_outlined,
      'cloud' => Icons.cloud_rounded,
      'fog' => Icons.foggy,
      'rain' => Icons.water_drop_rounded,
      'snow' => Icons.ac_unit_rounded,
      'storm' => Icons.thunderstorm_rounded,
      _ => Icons.cloud_rounded,
    };

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.future, required this.city, this.onRetry});
  final Future<Weather> future;
  final City city;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final cs = Theme.of(context).colorScheme;
    String lbl(int code) {
      final l = weatherLabel(code);
      return switch (lang) { AppLang.ps => l.ps, AppLang.fa => l.fa, AppLang.en => l.en };
    }

    return _Section(
      icon: Icons.wb_sunny_rounded,
      color: Brand.saffronDeep,
      title: '${context.tr('weather')} · ${city.name(lang)}',
      trailing: 'Open-Meteo',
      child: _Async<Weather>(
        future: future,
        onRetry: onRetry,
        builder: (w) => Column(
          children: [
            Row(
              children: [
                Icon(_weatherIcon(weatherLabel(w.code).icon), size: 54, color: Brand.saffron),
                const SizedBox(width: 14),
                Text(
                  localDigits('${w.temp.round()}°', lang),
                  style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1.1),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lbl(w.code), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                      Text(
                        localDigits(
                          '${context.tr('feels_like')} ${w.feels.round()}° · ${context.tr('wind')} \u2066${w.wind.round()} km/h\u2069 · ${context.tr('humidity')} ${w.humidity}٪',
                          lang,
                        ),
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final d in w.days)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          Text(
                            sameDay(d.date, DateTime.now()) ? context.tr('today') : weekdayName(d.date, lang),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Icon(_weatherIcon(weatherLabel(d.code).icon), size: 22, color: Brand.saffronDeep),
                          const SizedBox(height: 6),
                          Text(localDigits('${d.max.round()}°', lang), style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(localDigits('${d.min.round()}°', lang), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Prayer times ──────────────────────────────────────────────────────────
class _PrayerCard extends StatelessWidget {
  const _PrayerCard({required this.future, required this.city, this.onRetry});
  final Future<PrayerTimes> future;
  final City city;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final cs = Theme.of(context).colorScheme;
    const keys = ['fajr', 'sunrise', 'dhuhr', 'asr', 'maghrib', 'isha'];
    return _Section(
      icon: Icons.mosque_rounded,
      color: const Color(0xFF1E8C6E),
      title: '${context.tr('prayer_times')} · ${city.name(lang)}',
      trailing: 'AlAdhan',
      child: _Async<PrayerTimes>(
        future: future,
        onRetry: onRetry,
        builder: (p) {
          // Highlight the next prayer.
          final now = TimeOfDay.now();
          final nowMin = now.hour * 60 + now.minute;
          String? next;
          for (final k in keys) {
            final parts = p.times[k]!.split(':');
            final m = int.parse(parts[0]) * 60 + int.parse(parts[1]);
            if (m > nowMin && k != 'sunrise') {
              next = k;
              break;
            }
          }
          next ??= 'fajr';
          return GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.6,
            children: [
              for (final k in keys)
                Container(
                  decoration: BoxDecoration(
                    color: k == next ? const Color(0xFF1E8C6E) : cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        context.tr(k),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: k == next ? Colors.white : cs.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        localDigits(p.times[k]!, lang),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: k == next ? Colors.white : cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── Exchange rates ────────────────────────────────────────────────────────
class _RatesCard extends StatelessWidget {
  const _RatesCard({required this.future, this.onRetry});
  final Future<Rates> future;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final cs = Theme.of(context).colorScheme;
    return _Section(
      icon: Icons.currency_exchange_rounded,
      color: Brand.lapis,
      title: '${context.tr('rates')} · ${context.tr('rates_sub')}',
      trailing: 'ExchangeRate-API',
      child: _Async<Rates>(
        future: future,
        onRetry: onRetry,
        builder: (r) => Column(
          children: [
            for (final x in r.list)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(8)),
                      child: Text(x.code, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      lang == AppLang.en
                          ? '${_fmtUnit(x.unit)} ${x.code}'
                          : localDigits('${x.unit == 1 ? '' : '${x.unit} '}${currencyName(x.code, lang)}', lang),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(
                      localDigits(x.afn >= 100 ? x.afn.toStringAsFixed(1) : x.afn.toStringAsFixed(2), lang),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 4),
                    Text('؋', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _fmtUnit(int u) => switch (u) { 1000 => '1,000', 1000000 => '1,000,000', _ => '$u' };
}

// ── Verse of the day ──────────────────────────────────────────────────────
class _AyahCard extends StatelessWidget {
  const _AyahCard({required this.future, this.onRetry});
  final Future<Ayah> future;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Section(
      icon: Icons.menu_book_rounded,
      color: const Color(0xFF6A3FA0),
      title: context.tr('ayah'),
      trailing: 'AlQuran Cloud',
      child: _Async<Ayah>(
        future: future,
        onRetry: onRetry,
        builder: (a) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              a.arabic,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, height: 1.9, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 10),
            Text(a.translation, style: TextStyle(fontSize: 15, height: 1.7, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(
              localDigits('${a.surah} · ${a.number}', context.lang),
              textAlign: TextAlign.end,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
