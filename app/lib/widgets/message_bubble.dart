import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';

final _rtlChars = RegExp(r'[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]');
final _ltrChars = RegExp(r'[A-Za-zÀ-ɏ]');

/// Direction from the first strong character, so English bubbles read
/// left-to-right inside a Pashto interface and vice versa.
TextDirection textDirOf(String s, TextDirection fallback) {
  for (final ch in s.characters) {
    if (_rtlChars.hasMatch(ch)) return TextDirection.rtl;
    if (_ltrChars.hasMatch(ch)) return TextDirection.ltr;
  }
  return fallback;
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.showSender = false,
    this.tail = true,
  });

  final Message message;
  final bool showSender;
  final bool tail;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = message;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final text = app.display(m.text);

    if (m.system) return SystemChip(text: text);

    final out = m.outgoing;
    final bg = out
        ? (dark ? Brand.bubbleOutDark : Brand.bubbleOutLight)
        : (dark ? Brand.bubbleInDark : Brand.bubbleInLight);
    final fg = dark ? const Color(0xFFEDEFF6) : Brand.ink;
    final metaColor = dark ? const Color(0xFFA9B4D6) : const Color(0xFF6B7591);
    const r = Radius.circular(18);
    const small = Radius.circular(5);
    final radius = BorderRadiusDirectional.only(
      topStart: r,
      topEnd: r,
      bottomStart: (!out && tail) ? small : r,
      bottomEnd: (out && tail) ? small : r,
    );
    final width = MediaQuery.sizeOf(context).width;
    final dir = Directionality.of(context);

    return Align(
      alignment: out ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
        },
        onTap: m.status == MsgStatus.failed ? () => app.retry(m) : null,
        child: Container(
          margin: EdgeInsets.only(top: tail ? 6 : 2),
          constraints: BoxConstraints(maxWidth: (width * 0.78).clamp(0, 520)),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 7, 10, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06), blurRadius: 3, offset: const Offset(0, 1)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender && !out)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    app.display(m.senderName),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Brand.avatarColor(m.senderId),
                    ),
                  ),
                ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 10,
                children: [
                  Text(
                    text,
                    textDirection: textDirOf(text, dir),
                    style: TextStyle(fontSize: 15.5, height: 1.45, color: fg),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(hhmm(m.time, context.lang), style: TextStyle(fontSize: 11.5, color: metaColor)),
                        if (out) ...[
                          const SizedBox(width: 3),
                          _StatusIcon(status: m.status, color: metaColor),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status, required this.color});
  final MsgStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      MsgStatus.sending => Icon(Icons.schedule_rounded, size: 15, color: color),
      MsgStatus.sent => Icon(Icons.done_rounded, size: 16, color: color),
      MsgStatus.delivered => Icon(Icons.done_all_rounded, size: 16, color: color),
      MsgStatus.read => const Icon(Icons.done_all_rounded, size: 16, color: Brand.saffronDeep),
      MsgStatus.failed => const Icon(Icons.error_outline_rounded, size: 16, color: Brand.pomegranate),
    };
  }
}

/// Centered pill used for dates and notices.
class SystemChip extends StatelessWidget {
  const SystemChip({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: dark ? const Color(0xCC1C2640) : const Color(0xE6FFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: dark ? const Color(0xFFB8C2DE) : Brand.slate,
          ),
        ),
      ),
    );
  }
}
