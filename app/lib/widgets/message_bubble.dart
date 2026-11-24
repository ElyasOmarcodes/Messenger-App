import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
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
  const MessageBubble({super.key, required this.chat, required this.message, this.senderName, this.tail = true, this.onReply});

  final Chat chat;
  final Message message;

  /// Shown above the first message of a run in groups.
  final String? senderName;
  final bool tail;
  final void Function(Message)? onReply;

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
        onLongPress: m.deleted || m.pending ? null : () => _menu(context, app, out),
        onSecondaryTap: m.deleted || m.pending ? null : () => _menu(context, app, out),
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
              if (m.replyTo != null && !m.deleted) _ReplyQuote(chat: chat, id: m.replyTo!),
              if (m.deleted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.block_rounded, size: 16, color: metaColor),
                    const SizedBox(width: 6),
                    Text(context.tr('deleted'), style: TextStyle(fontStyle: FontStyle.italic, color: metaColor)),
                    const SizedBox(width: 10),
                    meta,
                  ]),
                )
              else ...[
              if (m.kind == MsgKind.voice) VoicePlayer(message: m, color: fg, meta: metaColor),
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
              ],
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

extension on MessageBubble {
  void _menu(BuildContext context, AppController app, bool out) {
    final m = message;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(ctx.tr('reply')),
                onTap: () {
                  Navigator.pop(ctx);
                  onReply!(m);
                },
              ),
            if (m.body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text(ctx.tr('copy')),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: m.body));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
                },
              ),
            if (out && !m.failed)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Brand.pomegranate),
                title: Text(ctx.tr('delete'), style: const TextStyle(color: Brand.pomegranate)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      content: Text(d.tr('delete_q')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: Text(d.tr('delete'), style: const TextStyle(color: Brand.pomegranate))),
                      ],
                    ),
                  );
                  if (ok == true) await app.deleteMessage(chat, m);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Small quoted block above a reply.
class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.chat, required this.id});
  final Chat chat;
  final String id;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = app.messageById(chat.id, id);
    final who = q == null ? '' : (q.senderId == app.myId ? context.tr('you') : (app.memberById(chat, q.senderId)?.name ?? ''));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: Brand.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: const BorderDirectional(start: BorderSide(color: Brand.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(who, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Brand.accentDeep)),
          Text(q == null ? '…' : app.previewOf(q), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

/// Play/pause button with a progress bar for voice notes.
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, required this.message, required this.color, required this.meta});
  final Message message;
  final Color color;
  final Color meta;

  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  Duration _pos = Duration.zero;
  Duration? _dur;
  bool _playing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final ms = widget.message.durationMs;
    if (ms != null) _dur = Duration(milliseconds: ms);
    _subs.add(_player.onPositionChanged.listen((p) => setState(() => _pos = p)));
    _subs.add(_player.onDurationChanged.listen((d) => setState(() => _dur = d)));
    _subs.add(_player.onPlayerComplete.listen((_) => setState(() {
          _playing = false;
          _pos = Duration.zero;
        })));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    final m = widget.message;
    setState(() => _loading = true);
    try {
      if (_pos > Duration.zero) {
        await _player.resume();
      } else if (m.localBytes != null) {
        await _player.play(BytesSource(m.localBytes!, mimeType: m.mimeType));
      } else if (m.filePath != null) {
        final url = await AppScope.read(context).fileUrl(m.filePath!);
        if (url != null) await _player.play(UrlSource(url, mimeType: m.mimeType));
      }
      setState(() => _playing = true);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _dur ?? Duration.zero;
    final progress = total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: 230,
      child: Row(
        children: [
          Material(
            color: Brand.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.message.pending || _loading ? null : _toggle,
              child: SizedBox(
                width: 44,
                height: 44,
                child: _loading || widget.message.pending
                    ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 5,
                    backgroundColor: widget.meta.withValues(alpha: 0.25),
                    color: Brand.accentDeep,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  localDigits(_fmt(_playing || _pos > Duration.zero ? _pos : total), context.lang),
                  style: TextStyle(fontSize: 12, color: widget.meta),
                ),
              ],
            ),
          ),
        ],
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
        MsgStatus.read => Icon(Icons.done_all_rounded, size: 16, color: Theme.of(context).brightness == Brightness.dark ? Brand.blueBright : Brand.blueDeep),
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
