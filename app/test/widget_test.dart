import 'package:flutter_test/flutter_test.dart';
import 'package:paigham/l10n/afghan_date.dart';
import 'package:paigham/l10n/strings.dart';
import 'package:paigham/models/models.dart';

void main() {
  test('Solar Hijri conversion matches known dates', () {
    final nowruz = SolarHijri.fromDate(DateTime(2026, 3, 21));
    expect([nowruz.year, nowruz.month, nowruz.day], [1405, 1, 1]);
    final d = SolarHijri.fromDate(DateTime(2026, 11, 24));
    expect([d.year, d.month, d.day], [1405, 9, 3]);
    expect(d.monthName(AppLang.fa), 'قوس');
    expect(d.monthName(AppLang.ps), 'لیندۍ');
  });

  test('Eastern digits for Pashto and Dari', () {
    expect(localDigits('12:45', AppLang.ps), '۱۲:۴۵');
    expect(localDigits('12:45', AppLang.en), '12:45');
  });

  test('IDs are generated, prettified and parsed back', () {
    final id = randomId(10);
    expect(isValidUserId(id), isTrue);
    final pretty = prettyId(id);
    expect(pretty.length, 11);
    expect(normalizeId(pretty), id);
    expect(isValidUserId('hello'), isFalse);
  });
}
