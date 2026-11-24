import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
  const MessageBubble({super.key, required this.chat, required this.message, this.senderName, this.tail = true});

  final Chat chat;
  final Message message;

  /// Shown above the first message of a run in groups.
  final String? senderName;
  final bool tail;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final m = message;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final out = m.senderId == app.myId;
    final bg = out ? (dark ? Brand.bubbleOutDark : Brand.bubbleOutLight) : (dark ? Brand.bubbleInDark : Brand.bubbleInLight);
    final fg = dark ? const Color(0xFFEDEFF6) : Brand.ink;
    final metaColor = dark ? const Color(0xFFA9B4D6) : const Color(0xFF6B7591);
    const r = Radius.circular(18);
    const small = Radius.circular(5);
    final width = MediaQuery.sizeOf(context).width;
    final dir = Directionality.of(context);
    final isImage = m.kind == MsgKind.image;

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(hhmm(m.createdAt, context.lang), style: TextStyle(fontSize: 11.5, color: metaColor)),
        if (out) ...[const SizedBox(width: 3), _StatusIcon(status: app.statusOf(chat, m), color: metaColor)],
      ],
    );

    return Align(
      alignment: out ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: GestureDetector(
        onLongPress: m.body.isEmpty
            ? null
            : () {
                Clipboard.setData(ClipboardData(text: m.body));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
              },
        onTap: m.failed ? () => app.retry(chat, m) : null,
        child: Container(
          margin: EdgeInsets.only(top: tail ? 6 : 2),
          constraints: BoxConstraints(maxWidth: (width * 0.78).clamp(0, isImage ? 360 : 520)),
          padding: isImage ? const EdgeInsets.all(4) : const EdgeInsetsDirectional.fromSTEB(12, 7, 10, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadiusDirectional.only(
              topStart: r,
              topEnd: r,
              bottomStart: (!out && tail) ? small : r,
              bottomEnd: (out && tail) ? small : r,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.25 : 0.06), blurRadius: 3, offset: const Offset(0, 1))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (senderName != null && !out)
                Padding(
                  padding: EdgeInsets.fromLTRB(isImage ? 8 : 0, isImage ? 4 : 0, isImage ? 8 : 0, 2),
                  child: Text(senderName!,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Brand.avatarColor(m.senderId))),
                ),
              if (isImage) _ImageContent(message: m),
              if (m.kind == MsgKind.file) _FileContent(message: m, color: fg, meta: metaColor),
              if (m.body.isNotEmpty || m.kind == MsgKind.text)
                Padding(
                  padding: isImage ? const EdgeInsets.fromLTRB(8, 6, 8, 2) : EdgeInsets.zero,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 10,
                    children: [
                      Text(m.body, textDirection: textDirOf(m.body, dir), style: TextStyle(fontSize: 15.5, height: 1.45, color: fg)),
                      Padding(padding: const EdgeInsets.only(top: 2), child: meta),
                    ],
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, isImage ? 2 : 0),
                  child: Align(alignment: AlignmentDirectional.centerEnd, child: meta),
                ),
              if (m.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(context.tr('send_failed'), style: const TextStyle(fontSize: 12, color: Brand.pomegranate)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.message});
  final Message message;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    final m = message;
    Widget frame(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 180, minHeight: 120, maxHeight: 340), child: child),
        );
    if (m.localBytes != null) {
      return frame(Stack(alignment: Alignment.center, children: [
        Image.memory(m.localBytes!, fit: BoxFit.cover),
        if (m.pending) const CircularProgressIndicator(color: Colors.white),
      ]));
    }
    if (m.filePath == null) return const SizedBox.shrink();
    return FutureBuilder<String?>(
      future: app.fileUrl(m.filePath!),
      builder: (context, snap) {
        final url = snap.data;
        if (url == null) {
          return frame(Container(
            color: Colors.black12,
            height: 180,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          ));
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ImageViewer(url: url, name: m.fileName ?? ''))),
          child: frame(Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (c, child, p) =>
                p == null ? child : Container(color: Colors.black12, height: 180, child: const Center(child: CircularProgressIndicator(strokeWidth: 2.4))),
            errorBuilder: (_, _, _) => Container(color: Colors.black12, height: 120, child: const Center(child: Icon(Icons.broken_image_outlined))),
          )),
        );
      },
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          title: Text(name, style: const TextStyle(fontSize: 15)),
          actions: [
            IconButton(
              icon: const Icon(Icons.download_rounded),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
          ],
        ),
        body: InteractiveViewer(maxScale: 5, child: Center(child: Image.network(url))),
      );
}

class _FileContent extends StatelessWidget {
  const _FileContent({required this.message, required this.color, required this.meta});
  final Message message;
  final Color color;
  final Color meta;

  IconData get _icon {
    final mime = message.mimeType ?? '';
    if (mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
    if (mime.startsWith('audio/')) return Icons.audiotrack_rounded;
    if (mime.startsWith('video/')) return Icons.movie_rounded;
    if (mime.contains('zip')) return Icons.folder_zip_rounded;
    if (mime.contains('sheet') || mime.contains('excel')) return Icons.table_chart_rounded;
    if (mime.contains('word') || mime.startsWith('text/')) return Icons.description_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Future<void> _open(BuildContext context) async {
    if (message.filePath == null) return;
    final url = await AppScope.read(context).fileUrl(message.filePath!);
    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: message.pending ? null : () => _open(context),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: Brand.lapis, borderRadius: BorderRadius.circular(12)),
              child: message.pending
                  ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Icon(_icon, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.fileName ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                  Text(
                    message.pending ? context.tr('uploading') : '\u2066${localDigits(formatBytes(message.fileSize), context.lang)}\u2069',
                    style: TextStyle(fontSize: 12.5, color: meta),
                  ),
                ],
              ),
            ),
          ],
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
  Widget build(BuildContext context) => switch (status) {
        MsgStatus.sending => Icon(Icons.schedule_rounded, size: 15, color: color),
        MsgStatus.sent => Icon(Icons.done_rounded, size: 16, color: color),
        MsgStatus.read => const Icon(Icons.done_all_rounded, size: 16, color: Brand.accentDeep),
        MsgStatus.failed => const Icon(Icons.error_outline_rounded, size: 16, color: Brand.pomegranate),
      };
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
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: dark ? const Color(0xFFB8C2DE) : Brand.slate)),
      ),
    );
  }
}
