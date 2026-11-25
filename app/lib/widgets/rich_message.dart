import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Telegram-style formatting in messages (what Telegram's own markdown
/// understands, plus underline):
///
///   **bold**  __italic__  ++underline++  ~~strike~~  ||spoiler||
///   `code`    ```code block```    > quote (at the start of a line)
///   links (https://…, www.…, paigham://…), @username, #hashtag
///
/// Written by hand on purpose: a few hundred lines that parse in one pass,
/// instead of a full Markdown package (headings, tables… that chats never
/// use) on every bubble.
class RichMessageText extends StatefulWidget {
  const RichMessageText({super.key, required this.text, required this.style, required this.linkColor, this.textDirection, this.onLink});
  final String text;
  final TextStyle style;
  final Color linkColor;
  final TextDirection? textDirection;

  /// Taps on links, @mentions and #hashtags (null: links open in the browser).
  final void Function(String link)? onLink;

  /// True when [text] has nothing to format (the fast path).
  static bool isPlain(String text) => !_marks.hasMatch(text);
  static final _marks = RegExp(r'\*\*|__|\+\+|~~|\|\||`|^>|\n>|https?://|www\.|paigham://|@\w|#[^\s#]', unicode: true);

  /// The text without formatting marks (chat list, notifications, copy).
  static String strip(String text) {
    if (isPlain(text)) return text;
    return text
        .replaceAllMapped(RegExp(r'```(?:[a-zA-Z0-9]+\n)?([\s\S]*?)```'), (m) => m[1]!)
        .replaceAll(RegExp(r'\*\*|__|\+\+|~~|\|\||`'), '')
        .replaceAll(RegExp(r'^> ?', multiLine: true), '');
  }

  @override
  State<RichMessageText> createState() => _RichMessageTextState();
}

class _RichMessageTextState extends State<RichMessageText> {
  final List<TapGestureRecognizer> _taps = [];
  bool _revealed = false; // spoilers shown after a tap

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _tap(VoidCallback f) {
    final t = TapGestureRecognizer()..onTap = f;
    _taps.add(t);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    if (RichMessageText.isPlain(widget.text)) {
      return Text(widget.text, textDirection: widget.textDirection, style: widget.style);
    }
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    return Text.rich(
      TextSpan(children: _blocks(widget.text)),
      textDirection: widget.textDirection,
      style: widget.style,
    );
  }

  // ── blocks: quotes and code blocks ────────────────────────────────────────
  List<InlineSpan> _blocks(String text) {
    final out = <InlineSpan>[];
    final pre = RegExp(r'```(?:([a-zA-Z0-9]+)\n)?([\s\S]*?)```');
    var i = 0;
    for (final m in pre.allMatches(text)) {
      if (m.start > i) out.addAll(_quotes(text.substring(i, m.start)));
      out.add(_codeBlock(m[2]!.replaceAll(RegExp(r'^\n|\n$'), ''), m[1]));
      i = m.end;
    }
    if (i < text.length) out.addAll(_quotes(text.substring(i)));
    return out;
  }

  List<InlineSpan> _quotes(String text) {
    if (!text.contains(RegExp(r'(^|\n)>'))) return _inline(text, const _Fmt());
    final out = <InlineSpan>[];
    final lines = text.split('\n');
    final normal = <String>[];
    final quote = <String>[];
    void flushNormal({bool more = false}) {
      if (normal.isEmpty) return;
      out.addAll(_inline(normal.join('\n') + (more ? '\n' : ''), const _Fmt()));
      normal.clear();
    }

    void flushQuote() {
      if (quote.isEmpty) return;
      out.add(_quoteBlock(quote.join('\n')));
      quote.clear();
    }

    for (final l in lines) {
      if (l.startsWith('>')) {
        flushNormal(more: true);
        quote.add(l.replaceFirst(RegExp(r'^> ?'), ''));
      } else {
        flushQuote();
        normal.add(l);
      }
    }
    flushNormal();
    flushQuote();
    return out;
  }

  InlineSpan _quoteBlock(String text) {
    final c = widget.linkColor;
    return WidgetSpan(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsetsDirectional.fromSTEB(9, 4, 8, 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: BorderDirectional(start: BorderSide(color: c, width: 3)),
        ),
        child: Text.rich(TextSpan(children: _inline(text, const _Fmt())), style: widget.style),
      ),
    );
  }

  InlineSpan _codeBlock(String code, String? lang) {
    final c = widget.linkColor;
    return WidgetSpan(
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (lang != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    lang,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c),
                  ),
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  code,
                  style: widget.style.copyWith(fontFamily: 'monospace', fontSize: (widget.style.fontSize ?? 16) - 2, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── inline styles ─────────────────────────────────────────────────────────
  static const _pairs = ['**', '__', '++', '~~', '||'];

  List<InlineSpan> _inline(String s, _Fmt f) {
    final out = <InlineSpan>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isEmpty) return;
      out.addAll(_links(buf.toString(), f));
      buf.clear();
    }

    var i = 0;
    outer:
    while (i < s.length) {
      if (s.codeUnitAt(i) == 0x60) {
        // `code`
        final j = s.indexOf('`', i + 1);
        if (j > i + 1) {
          flush();
          out.add(TextSpan(text: s.substring(i + 1, j), style: _style(f.copy(code: true))));
          i = j + 1;
          continue;
        }
      }
      for (final p in _pairs) {
        if (s.startsWith(p, i)) {
          final j = s.indexOf(p, i + 2);
          if (j > i + 2) {
            flush();
            out.addAll(_inline(s.substring(i + 2, j), f.add(p)));
            i = j + 2;
            continue outer;
          }
        }
      }
      buf.writeCharCode(s.codeUnitAt(i));
      i++;
    }
    flush();
    return out;
  }

  static final _link = RegExp(r'(https?://[^\s<>]+|www\.[^\s<>]+|paigham://[^\s<>]+)|(@[A-Za-z0-9_]{3,32})|(#[^\s#.,!?؟،]+)', unicode: true);

  List<InlineSpan> _links(String s, _Fmt f) {
    if (f.spoiler && !_revealed) {
      // hidden: a soft block in the text colour until tapped
      return [
        TextSpan(
          text: s,
          style: (_style(f) ?? const TextStyle()).copyWith(
            color: Colors.transparent,
            backgroundColor: (widget.style.color ?? Colors.grey).withValues(alpha: 0.35),
          ),
          recognizer: _tap(() => setState(() => _revealed = true)),
        ),
      ];
    }
    final out = <InlineSpan>[];
    var i = 0;
    for (final m in _link.allMatches(s)) {
      if (m.start > i) out.add(TextSpan(text: s.substring(i, m.start), style: _style(f)));
      var t = m[0]!;
      // a link does not end in punctuation
      final tail = RegExp(r'[).,!?؟،:;]+$').firstMatch(t);
      final rest = tail == null ? '' : tail[0]!;
      if (rest.isNotEmpty) t = t.substring(0, t.length - rest.length);
      out.add(
        TextSpan(
          // isolated left-to-right, so "@name" and links keep their order in Pashto text
          text: '\u2066$t\u2069',
          style: (_style(f) ?? const TextStyle()).copyWith(
            color: widget.linkColor,
            decoration: m[1] != null ? TextDecoration.underline : null,
            decorationColor: widget.linkColor,
          ),
          recognizer: _tap(() => widget.onLink?.call(t)),
        ),
      );
      if (rest.isNotEmpty) out.add(TextSpan(text: rest, style: _style(f)));
      i = m.end;
    }
    if (i < s.length) out.add(TextSpan(text: s.substring(i), style: _style(f)));
    return out;
  }

  TextStyle? _style(_Fmt f) {
    if (f.plain) return null;
    final deco = <TextDecoration>[if (f.underline) TextDecoration.underline, if (f.strike) TextDecoration.lineThrough];
    return TextStyle(
      fontWeight: f.bold ? FontWeight.w700 : null,
      fontStyle: f.italic ? FontStyle.italic : null,
      decoration: deco.isEmpty ? null : TextDecoration.combine(deco),
      fontFamily: f.code ? 'monospace' : null,
      backgroundColor: f.code ? widget.linkColor.withValues(alpha: 0.12) : null,
      color: f.code ? widget.linkColor : null,
    );
  }
}

class _Fmt {
  const _Fmt({this.bold = false, this.italic = false, this.underline = false, this.strike = false, this.spoiler = false, this.code = false});
  final bool bold, italic, underline, strike, spoiler, code;

  bool get plain => !bold && !italic && !underline && !strike && !spoiler && !code;

  _Fmt add(String mark) => switch (mark) {
    '**' => copy(bold: true),
    '__' => copy(italic: true),
    '++' => copy(underline: true),
    '~~' => copy(strike: true),
    _ => copy(spoiler: true),
  };

  _Fmt copy({bool? bold, bool? italic, bool? underline, bool? strike, bool? spoiler, bool? code}) => _Fmt(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    spoiler: spoiler ?? this.spoiler,
    code: code ?? this.code,
  );
}

/// Wraps the selected text of [c] in a formatting mark (the composer's
/// Bold / Italic / … menu). With no selection the marks are inserted with
/// the cursor between them.
void wrapSelection(TextEditingController c, String open, [String? close]) {
  close ??= open;
  final sel = c.selection;
  final text = c.text;
  if (!sel.isValid) return;
  final start = sel.start, end = sel.end;
  final inner = text.substring(start, end);
  c.value = TextEditingValue(
    text: text.replaceRange(start, end, '$open$inner$close'),
    selection: inner.isEmpty
        ? TextSelection.collapsed(offset: start + open.length)
        : TextSelection(baseOffset: start + open.length, extentOffset: start + open.length + inner.length),
  );
}
