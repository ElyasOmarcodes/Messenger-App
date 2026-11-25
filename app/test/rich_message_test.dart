import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paigham/widgets/rich_message.dart';

void main() {
  test('plain text takes the fast path', () {
    expect(RichMessageText.isPlain('سلام، څنګه یې؟'), isTrue);
    expect(RichMessageText.isPlain('**غټ**'), isFalse);
    expect(RichMessageText.isPlain('see https://x.af'), isFalse);
  });

  test('strip removes marks for previews', () {
    expect(RichMessageText.strip('**غټ** او __کوږ__ ||پټ||'), 'غټ او کوږ پټ');
    expect(RichMessageText.strip('> نقل\nځواب'), 'نقل\nځواب');
    expect(RichMessageText.strip('```dart\nprint(1);```'), 'print(1);');
  });

  test('wrapSelection wraps the selected words', () {
    final c = TextEditingController(text: 'hello world');
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    wrapSelection(c, '**');
    expect(c.text, 'hello **world**');
  });

  testWidgets('formatted text renders styled spans', (t) async {
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RichMessageText(text: '**bold** `code` @someone', style: TextStyle(fontSize: 16), linkColor: Colors.blue),
        ),
      ),
    );
    final rich = t.widget<Text>(find.byType(Text).first).textSpan! as TextSpan;
    final flat = <TextSpan>[];
    rich.visitChildren((s) {
      if (s is TextSpan && s.text != null) flat.add(s);
      return true;
    });
    expect(flat.firstWhere((s) => s.text == 'bold').style!.fontWeight, FontWeight.w700);
    expect(flat.firstWhere((s) => s.text == 'code').style!.fontFamily, 'monospace');
    expect(flat.firstWhere((s) => s.text == '\u2066@someone\u2069').style!.color, Colors.blue);
  });
}
