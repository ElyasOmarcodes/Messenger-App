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
import 'effects.dart';
import 'media_views.dart';

final _rtlChars = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF]');
final _ltrChars = RegExp(r'[A-Za-z\u00C0-\u024F]');

/// Direction from the first strong character, so English bubbles read
/// left-to-right inside a Pashto interface and vice versa.
bool _isEmojiRune(int r) =>
    (r >= 0x1F000 && r <= 0x1FAFF) ||
    (r >= 0x2600 && r <= 0x27BF) ||
    (r >= 0x2300 && r <= 0x23FF) ||
    (r >= 0x2B00 && r <= 0x2BFF) ||
    (r >= 0x2190 && r <= 0x21FF) ||
    r == 0x203C ||
    r == 0x2049 ||
    r == 0x2122 ||
    r == 0x2139 ||
    r == 0x3030 ||
    r == 0x303D ||
    r == 0x3297 ||
    r == 0x3299 ||
    r == 0xA9 ||
    r == 0xAE;

/// 1–3 when the text is only that many emoji (then it is drawn big), else 0.
int bigEmojiCount(String text) {
  final t = text.trim();
  if (t.isEmpty || t.length > 40) return 0;
  final chars = t.characters.where((c) => c.trim().isNotEmpty).toList();
  if (chars.isEmpty || chars.length > 3) return 0;
  for (final c in chars) {
    if (!_isEmojiRune(c.runes.first)) return 0;
  }
  return chars.length;
}

TextDirection textDirOf(String s, TextDirection fallback) {
  for (final ch in s.characters) {
    if (_rtlChars.hasMatch(ch)) return TextDirection.rtl;
    if (_ltrChars.hasMatch(ch)) return TextDirection.ltr;
  }
  return fallback;
}

/// Reactions offered in the long-press menu.
const quickReactions = ['\u2764\uFE0F', '\u{1F44D}', '\u{1F602}', '\u{1F62E}', '\u{1F622}', '\u{1F64F}'];

/// Actions chosen from the long-press menu.
enum MsgAction { reply, copy, edit, pin, forward, save, delete }

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.chat,
    required this.message,
    this.senderName,
    this.pos = GroupPos.single,
    this.onReply,
    this.onAction,
    this.onOpenUser,
  });

  final Chat chat;
  final Message message;

  /// Shown above the first message of a run in groups.
  final String? senderName;
  final GroupPos pos;
  final void Function(Message)? onReply;
  final void Function(Message, MsgAction)? onAction;
  final void Function(String userId)? onOpenUser;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  double _drag = 0;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _drag = _dragStart * (1 - _back.value)));
  double _dragStart = 0;
  bool _fired = false;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  // Swipe toward the start edge (left in LTR, right in RTL) to reply.
  void _onDrag(DragUpdateDetails d, bool rtl) {
    final delta = rtl ? d.delta.dx : -d.delta.dx;
    setState(() => _drag = (_drag + delta).clamp(0.0, 90.0));
    if (_drag > 60 && !_fired) {
      _fired = true;
      HapticFeedback.lightImpact();
    }
  }

  void _onDragEnd() {
    if (_fired) widget.onReply?.call(widget.message);
    _fired = false;
    _dragStart = _drag;
    _back.forward(from: 0);
  }

  Future<void> _openMenu() async {
    final app = AppScope.read(context);
    final m = widget.message;
    final mine = m.senderId == app.myId;
    HapticFeedback.mediumImpact();
    final result = await showGeneralDialog<Object>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'menu',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, _) => _ContextMenu(
        chat: widget.chat,
        message: m,
        mine: mine,
        preview: HeroMode(enabled: false, child: _bubble(ctx, interactive: false)),
      ),
    );
    if (!mounted || result == null) return;
    if (result is String) {
      await app.react(widget.chat, m, result);
    } else if (result is MsgAction) {
      if (result == MsgAction.copy) {
        await Clipboard.setData(ClipboardData(text: m.body));
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
      } else {
        widget.onAction?.call(m, result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final out = widget.message.senderId == app.myId;
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: widget.onReply == null ? null : (d) => _onDrag(d, rtl),
      onHorizontalDragEnd: widget.onReply == null ? null : (_) => _onDragEnd(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Reply arrow appears on the end side while swiping.
          PositionedDirectional(
            end: 8,
            top: 0,
            bottom: 0,
            child: Opacity(
              opacity: (_drag / 60).clamp(0.0, 1.0),
              child: Center(
                child: Transform.scale(
                  scale: 0.6 + 0.4 * (_drag / 60).clamp(0.0, 1.0),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: cs.primary.withValues(alpha: 0.18),
                    child: Icon(Icons.reply_rounded, size: 20, color: cs.primary),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset((rtl ? 1 : -1) * _drag, 0),
            child: Align(alignment: out ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart, child: _bubble(context, interactive: true)),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, {required bool interactive}) {
    final app = AppScope.of(context);
    final m = widget.message;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final out = m.senderId == app.myId;
    final bg = out ? (dark ? Brand.bubbleOutDark : Brand.bubbleOutLight) : (dark ? Brand.bubbleInDark : Brand.bubbleInLight);
    final fg = dark ? const Color(0xFFF2F4F7) : Brand.ink;
    final metaColor = out ? (dark ? const Color(0xFF8FB8E6) : const Color(0xFF5B8FC7)) : (dark ? const Color(0xFF7F91A4) : const Color(0xFF8A93A0));
    final media = m.kind == MsgKind.image || m.kind == MsgKind.album || m.kind == MsgKind.location;
    final width = MediaQuery.sizeOf(context).width;
    final tailOnRight = out ? !rtl : rtl;
    final reacts = app.reactions[m.id] ?? const <String, String>{};
    final gap = widget.pos == GroupPos.single || widget.pos == GroupPos.first ? 6.0 : 2.0;
    // Photos carry their time on top of the picture; cards keep it underneath.
    final mediaOnly = media && m.kind != MsgKind.location && m.body.isEmpty;

    final time = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.edited) Text('${context.tr('edited')} ', style: TextStyle(fontSize: 11.5, color: mediaOnly ? Colors.white : metaColor)),
        Text(hhmm(m.createdAt, context.lang), style: TextStyle(fontSize: 11.5, color: mediaOnly ? Colors.white : metaColor)),
        if (out) ...[const SizedBox(width: 3), _StatusIcon(status: app.statusOf(widget.chat, m), color: mediaOnly ? Colors.white : metaColor)],
      ],
    );

    Widget content;
    switch (m.kind) {
      case MsgKind.image:
        final box = photoBox(m.width, m.height, maxW: (width * 0.72).clamp(150, 300));
        content = GestureDetector(
          onTap: () => GalleryViewer.open(context, [(path: m.filePath, bytes: m.localBytes)], 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: box.width,
              height: box.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: photoHeroTag((path: m.filePath, bytes: m.localBytes)),
                    child: AttachmentImage(path: m.filePath, bytes: m.localBytes),
                  ),
                  if (m.pending) const Center(child: CircularProgressIndicator(color: Colors.white)),
                ],
              ),
            ),
          ),
        );
      case MsgKind.album:
        content = AlbumGrid(message: m, width: (width * 0.72).clamp(200, 300));
      case MsgKind.location:
        content = LocationCard(lat: (m.meta?['lat'] as num?)?.toDouble() ?? 0, lng: (m.meta?['lng'] as num?)?.toDouble() ?? 0);
      case MsgKind.contact:
        content = ContactCard(meta: m.meta ?? const {}, onMessage: widget.onOpenUser);
      case MsgKind.voice:
        content = VoicePlayer(message: m, color: fg, meta: metaColor);
      case MsgKind.file:
        content = _FileContent(message: m, color: fg, meta: metaColor);
      case MsgKind.text:
        content = const SizedBox.shrink();
    }

    final textPart = m.body.isEmpty && m.kind != MsgKind.text
        ? null
        : Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 10,
            children: [
              Text(
                m.body,
                textDirection: textDirOf(m.body, Directionality.of(context)),
                style: TextStyle(fontSize: 16, height: 1.4, color: fg),
              ),
              Padding(padding: const EdgeInsets.only(top: 3), child: time),
            ],
          );

    final shrink = textPart == null && !mediaOnly;
    Widget body = Column(
      crossAxisAlignment: shrink ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.senderName != null && !out)
          Padding(
            padding: EdgeInsets.fromLTRB(media ? 6 : 0, media ? 2 : 0, media ? 6 : 0, 3),
            child: Text(
              widget.senderName!,
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Brand.avatarColor(m.senderId)),
            ),
          ),
        if (m.replyTo != null) _ReplyQuote(chat: widget.chat, id: m.replyTo!),
        if (m.kind != MsgKind.text)
          Stack(
            children: [
              content,
              if (mediaOnly)
                PositionedDirectional(
                  end: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(10)),
                    child: time,
                  ),
                ),
            ],
          ),
        if (textPart != null)
          Padding(padding: EdgeInsets.fromLTRB(media ? 6 : 0, media ? 6 : 0, media ? 6 : 0, media ? 2 : 0), child: textPart)
        else if (!mediaOnly)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(padding: const EdgeInsets.only(top: 2), child: time),
          ),
        if (reacts.isNotEmpty) _Reactions(chat: widget.chat, message: m, reactions: reacts, interactive: interactive),
        if (m.failed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.tr('send_failed'), style: const TextStyle(fontSize: 12, color: Brand.pomegranate)),
          ),
      ],
    );

    // Voice, file, contact and location cards: the bubble hugs the card.
    if (shrink) body = IntrinsicWidth(child: body);

    // A few emoji alone: shown big, without a bubble (like Telegram).
    final emojiCount = m.kind == MsgKind.text && m.replyTo == null && !m.deleted ? bigEmojiCount(m.body) : 0;
    if (emojiCount > 0) {
      return GestureDetector(
        onTap: !interactive ? null : (m.failed ? () => app.retry(widget.chat, m) : (m.pending ? null : _openMenu)),
        onLongPress: !interactive || m.pending ? null : _openMenu,
        onSecondaryTap: !interactive || m.pending ? null : _openMenu,
        child: Padding(
          padding: EdgeInsets.only(top: gap + 2, left: 6, right: 6),
          child: Column(
            crossAxisAlignment: out ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(m.body, style: TextStyle(fontSize: const [0.0, 52.0, 44.0, 38.0][emojiCount], height: 1.15)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: dark ? const Color(0x66000000) : const Color(0x33000000), borderRadius: BorderRadius.circular(10)),
                child: DefaultTextStyle.merge(
                  style: const TextStyle(color: Colors.white),
                  child: IconTheme.merge(
                    data: const IconThemeData(color: Colors.white),
                    child: time,
                  ),
                ),
              ),
              if (reacts.isNotEmpty) _Reactions(chat: widget.chat, message: m, reactions: reacts, interactive: interactive),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      // Like Telegram on phones: one tap opens the message menu.
      onTap: !interactive ? null : (m.failed ? () => app.retry(widget.chat, m) : (m.pending ? null : _openMenu)),
      onLongPress: !interactive || m.pending ? null : _openMenu,
      onSecondaryTap: !interactive || m.pending ? null : _openMenu,
      child: Container(
        margin: EdgeInsets.only(top: gap),
        constraints: BoxConstraints(maxWidth: (width * 0.8).clamp(0, 480)),
        child: CustomPaint(
          painter: BubblePainter(color: bg, tailOnRight: tailOnRight, pos: widget.pos),
          child: Padding(
            padding: EdgeInsets.only(
              left: (tailOnRight ? 0 : kBubbleTail) + (media ? 3 : 11),
              right: (tailOnRight ? kBubbleTail : 0) + (media ? 3 : 11),
              top: media ? 3 : 7,
              bottom: media ? 3 : 6,
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Reaction chips under a message.
class _Reactions extends StatelessWidget {
  const _Reactions({required this.chat, required this.message, required this.reactions, required this.interactive});
  final Chat chat;
  final Message message;
  final Map<String, String> reactions;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final e in reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final mine = reactions[app.myId];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final e in counts.entries)
            GestureDetector(
              onTap: interactive ? () => app.react(chat, message, e.key) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: e.key == mine ? cs.primary : cs.primary.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(e.key, style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 4),
                    Text(
                      context.digits(e.value),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: e.key == mine ? Colors.white : cs.primary),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Long-press menu: reaction bar, the message itself, and actions.
class _ContextMenu extends StatelessWidget {
  const _ContextMenu({required this.chat, required this.message, required this.mine, required this.preview});
  final Chat chat;
  final Message message;
  final bool mine;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pinned = chat.pinnedMessageId == message.id;
    final items = <(IconData, String, MsgAction, bool)>[
      (Icons.reply_rounded, 'reply', MsgAction.reply, false),
      if (message.body.isNotEmpty) (Icons.copy_rounded, 'copy', MsgAction.copy, false),
      if (mine && const [MsgKind.text, MsgKind.image, MsgKind.album, MsgKind.file].contains(message.kind)) (Icons.edit_rounded, 'edit', MsgAction.edit, false),
      (pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded, pinned ? 'unpin' : 'pin', MsgAction.pin, false),
      (Icons.shortcut_rounded, 'forward', MsgAction.forward, false),
      if (!chat.isSaved) (Icons.bookmark_border_rounded, 'save_message', MsgAction.save, false),
      if (mine) (Icons.delete_outline_rounded, 'delete', MsgAction.delete, true),
    ];
    final panel = dark ? const Color(0xF0242F3D) : const Color(0xF5FFFFFF);
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // reactions
                  Align(
                    child: Material(
                      color: panel,
                      elevation: 6,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(28),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final e in quickReactions)
                              InkResponse(
                                onTap: () => Navigator.pop(context, e),
                                radius: 24,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(e, style: const TextStyle(fontSize: 28)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  IgnorePointer(
                    child: Align(alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart, child: preview),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                    child: Material(
                      color: panel,
                      elevation: 6,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: SizedBox(
                        width: 230,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final (icon, key, action, danger) in items)
                              InkWell(
                                onTap: () => Navigator.pop(context, action),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(icon, size: 21, color: danger ? Brand.pomegranate : cs.onSurfaceVariant),
                                      const SizedBox(width: 14),
                                      Text(context.tr(key), style: TextStyle(fontSize: 15.5, color: danger ? Brand.pomegranate : cs.onSurface)),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
    final cs = Theme.of(context).colorScheme;
    final q = app.messageById(chat.id, id);
    final who = q == null ? '' : (q.senderId == app.myId ? context.tr('you') : (app.memberById(chat, q.senderId)?.name ?? ''));
    final color = q == null ? cs.primary : (q.senderId == app.myId ? cs.primary : Brand.avatarColor(q.senderId));
    final icon = q == null ? null : app.previewIcon(q);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(9, 5, 10, 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: BorderDirectional(start: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            who,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Icon(icon, size: 15, color: color),
                ),
              Flexible(
                child: Text(q == null ? '...' : app.previewOf(q), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
              ),
            ],
          ),
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
    _subs.add(
      _player.onPlayerComplete.listen(
        (_) => setState(() {
          _playing = false;
          _pos = Duration.zero;
        }),
      ),
    );
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
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
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
                  child: LinearProgressIndicator(value: progress, minHeight: 5, backgroundColor: widget.meta.withValues(alpha: 0.25), color: Brand.accentDeep),
                ),
                const SizedBox(height: 5),
                Text(localDigits(_fmt(_playing || _pos > Duration.zero ? _pos : total), context.lang), style: TextStyle(fontSize: 12, color: widget.meta)),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Icon(_icon, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.fileName ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontWeight: FontWeight.w700, color: color),
                  ),
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
    MsgStatus.read => Icon(Icons.done_all_rounded, size: 16, color: color),
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
        decoration: BoxDecoration(color: dark ? const Color(0xCC1C2640) : const Color(0xE6FFFFFF), borderRadius: BorderRadius.circular(12)),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: dark ? const Color(0xFFB8C2DE) : Brand.slate),
        ),
      ),
    );
  }
}
