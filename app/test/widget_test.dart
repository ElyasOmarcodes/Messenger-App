import 'package:flutter_test/flutter_test.dart';
import 'package:paigham/l10n/afghan_date.dart';
import 'package:paigham/l10n/strings.dart';
import 'package:paigham/models/models.dart';
import 'package:paigham/services/messenger.dart';

void main() {
  test('Solar Hijri conversion matches known dates', () {
    final nowruz = SolarHijri.fromDate(DateTime(2026, 3, 21));
    expect([nowruz.year, nowruz.month, nowruz.day], [1405, 1, 1]);
    final d = SolarHijri.fromDate(DateTime(2026, 11, 24));
    expect([d.year, d.month, d.day], [1405, 9, 3]);
  });

  test('Eastern digits for Pashto and Dari', () {
    expect(localDigits('12:45', AppLang.ps), '۱۲:۴۵');
    expect(localDigits('12:45', AppLang.en), '12:45');
  });

  test('Message JSON from the server', () {
    final m = Message.fromJson({
      'id': 'a', 'chat_id': 'c', 'sender_id': 's', 'kind': 'image', 'body': '',
      'created_at': '2026-11-24T06:00:00Z', 'file_path': 'c/1-x.png', 'file_name': 'x.png', 'file_size': 2048,
    });
    expect(m.kind, MsgKind.image);
    expect(formatBytes(m.fileSize), '2 KB');
  });

  test('MIME types for attachments', () {
    expect(mimeFor('photo.JPG'), 'image/jpeg');
    expect(mimeFor('report.pdf'), 'application/pdf');
    expect(mimeFor('noext'), 'application/octet-stream');
  });
}
