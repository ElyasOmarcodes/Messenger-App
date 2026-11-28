import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../screens/stories.dart' show storyGradient;
import '../services/media_cache.dart';
import 'links.dart';
import 'rich_message.dart';
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
    this.onJump,
    this.onShowAll,
    this.onSelect,
  });

  final Chat chat;
  final Message message;

  /// Shown above the first message of a run in groups.
  final String? senderName;
  final GroupPos pos;
  final void Function(Message)? onReply;
  final void Function(Message, MsgAction)? onAction;
  final void Function(String userId)? onOpenUser;

  /// Scrolls the chat to a message (reply quote tap, "Show in chat").
  final void Function(String messageId)? onJump;

  /// Opens the chat's shared media.
  final VoidCallback? onShowAll;

  /// Long press: start selecting messages (Telegram); tap still opens the menu.
  final VoidCallback? onSelect;

  ViewerActions get viewerActions =>
      ViewerActions(chat: chat, onAction: onAction, onShowInChat: onJump == null ? null : (m) => onJump!(m.id), onShowAll: onShowAll);

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> with SingleTickerProviderStateMixin {
  double _drag = 0;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _drag = _dragStart * (1 - _back.value)));
  double _dragStart = 0;
  final _bubbleKey = GlobalKey();
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
    // so the keyboard does not pop up again when the menu closes
    FocusManager.instance.primaryFocus?.unfocus();
    final app = AppScope.read(context);
    final m = widget.message;
    final mine = m.senderId == app.myId;
    HapticFeedback.mediumImpact();
    // where the bubble is on screen, so the menu opens right at it
    final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    final anchor = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
    final glass = app.glass;
    final result = await showGeneralDialog<Object>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      pageBuilder: (ctx, _, _) => _ContextMenu(
        chat: widget.chat,
        message: m,
        mine: mine,
        anchor: anchor,
        glass: glass,
        preview: HeroMode(enabled: false, child: _bubble(ctx, interactive: false)),
      ),
    );
    if (!mounted || result == null) return;
    if (result is String) {
      await app.react(widget.chat, m, result);
    } else if (result is MsgAction) {
      if (result == MsgAction.copy) {
        await Clipboard.setData(ClipboardData(text: RichMessageText.strip(m.body)));
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
            child: Align(
              alignment: out ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
              child: KeyedSubtree(key: _bubbleKey, child: _bubble(context, interactive: true)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, {required bool interactive}) {
    final app = AppScope.of(context);
    final m = widget.message.locked ? widget.message.lockedAs(context.tr('locked_message')) : widget.message;
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
        content = Semantics(
          button: true,
          label: context.tr('photo'),
          child: GestureDetector(
            onTap: () => GalleryViewer.open(context, [(path: m.filePath, bytes: m.localBytes)], 0, messages: [m], actions: widget.viewerActions),
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
                      child: AttachmentImage(path: m.filePath, bytes: m.localBytes, size: m.fileSize),
                    ),
                    if (m.pending) Center(child: _SendingRing(onCancel: () => app.cancelSend(widget.chat, m))),
                  ],
                ),
              ),
            ),
          ),
        );
      case MsgKind.album:
        content = AlbumGrid(message: m, width: (width * 0.72).clamp(200, 300), actions: widget.viewerActions);
      case MsgKind.location:
        content = LocationCard(lat: (m.meta?['lat'] as num?)?.toDouble() ?? 0, lng: (m.meta?['lng'] as num?)?.toDouble() ?? 0);
      case MsgKind.contact:
        content = ContactCard(meta: m.meta ?? const {}, onMessage: widget.onOpenUser);
      case MsgKind.voice:
        content = VoicePlayer(message: m, color: fg, meta: metaColor);
      case MsgKind.file:
        content = _FileContent(chat: widget.chat, message: m, color: fg, meta: metaColor);
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
              RichMessageText(
                text: m.body,
                textDirection: textDirOf(m.body, Directionality.of(context)),
                style: TextStyle(fontSize: 16, height: 1.4, color: fg),
                linkColor: out ? (dark ? const Color(0xFF9FD0FF) : const Color(0xFF1F6FC5)) : (dark ? const Color(0xFF6AB7FF) : Brand.lapis),
                onLink: interactive ? (l) => openLink(context, l) : null,
              ),
              // with reactions, the time moves down beside them (it always ends the bubble)
              if (reacts.isEmpty || mediaOnly) Padding(padding: const EdgeInsets.only(top: 3), child: time),
            ],
          );

    final shrink = textPart == null && !mediaOnly;
    // A reply quote spans the whole bubble, like Telegram.
    final quoted = m.replyTo != null || m.meta?['story'] is Map;
    Widget body = Column(
      crossAxisAlignment: shrink || quoted ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
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
        if (m.replyTo != null)
          GestureDetector(
            onTap: widget.onJump == null ? null : () => widget.onJump!(m.replyTo!),
            child: _ReplyQuote(chat: widget.chat, id: m.replyTo!),
          ),
        if (m.meta?['story'] is Map) _StoryQuote(chat: widget.chat, story: Map<String, dynamic>.from(m.meta!['story'] as Map)),
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
        else if (!mediaOnly && reacts.isEmpty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(padding: const EdgeInsets.only(top: 2), child: time),
          ),
        if (reacts.isNotEmpty)
          mediaOnly
              ? _Reactions(chat: widget.chat, message: m, reactions: reacts, interactive: interactive)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: _Reactions(chat: widget.chat, message: m, reactions: reacts, interactive: interactive),
                    ),
                    const SizedBox(width: 8),
                    Padding(padding: const EdgeInsets.only(bottom: 2), child: time),
                  ],
                ),
        if (m.failed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(context.tr('send_failed'), style: const TextStyle(fontSize: 12, color: Brand.pomegranate)),
          ),
      ],
    );

    // Voice, file, contact and location cards: the bubble hugs the card.
    if (shrink || quoted) body = IntrinsicWidth(child: body);

    // A few emoji alone: shown big, without a bubble (like Telegram).
    final emojiCount = m.kind == MsgKind.text && m.replyTo == null && !m.deleted ? bigEmojiCount(m.body) : 0;
    if (emojiCount > 0) {
      return GestureDetector(
        onTap: !interactive ? null : (m.failed ? () => app.retry(widget.chat, m) : (m.pending ? null : _openMenu)),
        onLongPress: !interactive || m.pending ? null : (widget.onSelect ?? _openMenu),
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
      onLongPress: !interactive || m.pending ? null : (widget.onSelect ?? _openMenu),
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
  const _ContextMenu({required this.chat, required this.message, required this.mine, required this.preview, this.anchor, this.glass = true});
  final Chat chat;
  final Message message;
  final bool mine;
  final Widget preview;

  /// Where the bubble sits on screen; the menu opens right there.
  final Rect? anchor;
  final bool glass;

  static const _reactH = 50.0, _gap = 8.0, _rowH = 46.0, _menuW = 220.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pinned = chat.pinnedMessageId == message.id;
    final items = <(IconData, String, MsgAction, bool)>[
      (Icons.reply_rounded, 'reply', MsgAction.reply, false),
      if (message.body.isNotEmpty) (Icons.copy_rounded, 'copy', MsgAction.copy, false),
      if (mine && const [MsgKind.text, MsgKind.image, MsgKind.album, MsgKind.file].contains(message.kind)) (Icons.edit_rounded, 'edit', MsgAction.edit, false),
      if (chat.can(AppScope.read(context).myId ?? '', 'pin')) (Icons.push_pin_rounded, pinned ? 'unpin' : 'pin', MsgAction.pin, false),
      (Icons.shortcut_rounded, 'forward', MsgAction.forward, false),
      if (!chat.isSaved) (Icons.bookmark_rounded, 'save_message', MsgAction.save, false),
      if (mine || chat.can(AppScope.read(context).myId ?? '', 'delete') && chat.isGroup) (Icons.delete_rounded, 'delete', MsgAction.delete, true),
    ];
    final panel = dark ? const Color(0xF2232E3B) : const Color(0xF7FFFFFF);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final menuH = items.length * _rowH + 8;

    // Layout: reactions above the bubble, menu below; slide the whole group
    // up or down so it fits on screen.
    final r = anchor ?? Rect.fromCenter(center: size.center(Offset.zero), width: math.min(size.width * 0.8, 300), height: 60);
    final topLimit = pad.top + 8, bottomLimit = size.height - pad.bottom - 8;
    final maxPreview = math.max(60.0, bottomLimit - topLimit - _reactH - menuH - _gap * 2);
    final previewH = math.min(r.height, maxPreview);
    var top = r.top - _reactH - _gap; // top of the whole group
    final groupH = _reactH + _gap + previewH + _gap + menuH;
    if (top + groupH > bottomLimit) top = bottomLimit - groupH;
    if (top < topLimit) top = topLimit;
    final previewTop = top + _reactH + _gap;
    final menuTop = previewTop + previewH + _gap;
    final onLeft = r.center.dx < size.width / 2;
    double edgeX(double w) => onLeft ? r.left.clamp(8.0, size.width - w - 8) : (r.right - w).clamp(8.0, size.width - w - 8);
    final reactW = quickReactions.length * 44.0 + 12;
    final anim = ModalRoute.of(context)?.animation ?? const AlwaysStoppedAnimation(1.0);
    final pop = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);

    Widget glassPanel({required Widget child, required double radius}) {
      Widget p = Material(
        color: panel,
        elevation: 8,
        shadowColor: Colors.black38,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
      return p;
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // everything else: blurred and dimmed; a tap outside closes the menu
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: BackdropFilter(
                enabled: glass,
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: ColoredBox(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.18)),
              ),
            ),
          ),
          // the message itself, in the same place
          Positioned(
            left: r.left,
            top: previewTop,
            width: r.width,
            height: previewH,
            child: IgnorePointer(
              child: ClipRect(
                child: OverflowBox(alignment: Alignment.topLeft, maxHeight: double.infinity, child: preview),
              ),
            ),
          ),
          // quick reactions
          Positioned(
            left: edgeX(reactW),
            top: top,
            child: ScaleTransition(
              scale: pop,
              alignment: onLeft ? Alignment.bottomLeft : Alignment.bottomRight,
              child: glassPanel(
                radius: 28,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final e in quickReactions)
                        InkResponse(
                          onTap: () => Navigator.pop(context, e),
                          radius: 24,
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Center(child: Text(e, style: const TextStyle(fontSize: 27))),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // actions
          Positioned(
            left: edgeX(_menuW),
            top: menuTop,
            width: _menuW,
            child: ScaleTransition(
              scale: pop,
              alignment: onLeft ? Alignment.topLeft : Alignment.topRight,
              child: glassPanel(
                radius: 16,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (icon, key, action, danger) in items)
                        InkWell(
                          onTap: () => Navigator.pop(context, action),
                          child: SizedBox(
                            height: _rowH,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Icon(icon, size: 21, color: danger ? Brand.pomegranate : cs.onSurfaceVariant),
                                  const SizedBox(width: 14),
                                  Text(context.tr(key), style: TextStyle(fontSize: 15.5, color: danger ? Brand.pomegranate : cs.onSurface)),
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
        ],
      ),
    );
  }
}

/// Small quoted block above a reply.
/// Quote of a story this message answers (like Telegram's story reply).
class _StoryQuote extends StatefulWidget {
  const _StoryQuote({required this.chat, required this.story});
  final Chat chat;
  final Map<String, dynamic> story;

  @override
  State<_StoryQuote> createState() => _StoryQuoteState();
}

class _StoryQuoteState extends State<_StoryQuote> {
  @override
  void initState() {
    super.initState();
    // a sealed story's photo opens with the key carried in the (sealed) reply
    final p = widget.story['media_path'] as String?;
    if (p != null) AppScope.read(context).registerFileKey('stories/$p', widget.story['k'] as String?);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final owner = widget.story['owner'] as String?;
    final mine = owner == app.myId;
    final who = mine ? context.tr('my_story') : '${context.tr('story_label')} · ${owner == null ? '' : (app.memberById(widget.chat, owner)?.name ?? '')}';
    final color = cs.primary;
    final body = (widget.story['body'] as String?) ?? '';
    final image = widget.story['kind'] == 'image';
    final dpr = MediaQuery.devicePixelRatioOf(context);
    Widget thumb;
    if (image) {
      final p = widget.story['media_path'] as String;
      thumb = Image(
        image: ResizeImage(CachedImage('stories/$p', () => app.storyUrl(p)), width: (34 * dpr).round()),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(color: Colors.black26),
      );
    } else {
      thumb = Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: storyGradient(widget.story['bg'] as String?))),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(2),
        child: Text(
          body,
          maxLines: 3,
          overflow: TextOverflow.clip,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 5.5, height: 1.1, fontWeight: FontWeight.w700),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(9, 5, 6, 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: BorderDirectional(start: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 4),
                      child: Icon(Icons.auto_stories_rounded, size: 15, color: color),
                    ),
                    Flexible(
                      child: Text(
                        body.isNotEmpty ? body.replaceAll('\n', ' ') : context.tr('story_label'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(width: 34, height: 46, child: thumb),
          ),
        ],
      ),
    );
  }
}

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
  // The native player is made only when you press play (making one for
  // every voice note on screen made scrolling stutter).
  AudioPlayer? _p;
  final List<StreamSubscription<dynamic>> _subs = [];

  AudioPlayer get _player {
    final existing = _p;
    if (existing != null) return existing;
    final p = _p = AudioPlayer();
    _subs.add(p.onPositionChanged.listen((v) => setState(() => _pos = v)));
    _subs.add(p.onDurationChanged.listen((d) => setState(() => _dur = d)));
    _subs.add(
      p.onPlayerComplete.listen(
        (_) => setState(() {
          _playing = false;
          _pos = Duration.zero;
        }),
      ),
    );
    return p;
  }

  Duration _pos = Duration.zero;
  Duration? _dur;
  bool _playing = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final ms = widget.message.durationMs;
    if (ms != null) _dur = Duration(milliseconds: ms);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p?.dispose();
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
        final app = AppScope.read(context);
        final key = m.filePath!;
        final cache = MediaCache.instance;
        if (cache.persistent) {
          // played from the phone after the first time (also offline)
          if (cache.filePath(key) == null) await cache.bytes(key, () => app.fileUrl(key));
          final local = cache.filePath(key);
          if (local != null) {
            await _player.play(DeviceFileSource(local, mimeType: m.mimeType));
          } else if (m.fileKey == null) {
            final url = await app.fileUrl(key);
            if (url != null) await _player.play(UrlSource(url, mimeType: m.mimeType));
          }
        } else if (m.fileKey != null) {
          // encrypted: the link only gives ciphertext, so play the opened bytes
          final b = await cache.bytes(key, () => app.fileUrl(key));
          if (b != null) await _player.play(BytesSource(b, mimeType: m.mimeType));
        } else {
          final url = await app.fileUrl(key);
          if (url != null) await _player.play(UrlSource(url, mimeType: m.mimeType));
        }
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
    // Like Telegram: play on the left, waveform to the right, in every language.
    return SizedBox(
      width: 230,
      child: Directionality(
        textDirection: TextDirection.ltr,
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
                  SizedBox(
                    height: 26,
                    width: double.infinity,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _WavePainter(
                          seed: widget.message.id.hashCode,
                          progress: progress,
                          played: Brand.accentDeep,
                          rest: widget.meta.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(localDigits(_fmt(_playing || _pos > Duration.zero ? _pos : total), context.lang), style: TextStyle(fontSize: 12, color: widget.meta)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Voice-note waveform bars (a steady pattern per message), the played part coloured.
class _WavePainter extends CustomPainter {
  _WavePainter({required this.seed, required this.progress, required this.played, required this.rest});
  final int seed;
  final double progress;
  final Color played, rest;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 34;
    final step = size.width / bars;
    final w = math.max(2.0, step * 0.55);
    final r = math.Random(seed);
    final a = Paint()..color = played, b = Paint()..color = rest;
    var level = 0.4;
    for (var i = 0; i < bars; i++) {
      // a smooth random walk looks like speech
      level = (level + (r.nextDouble() - 0.5) * 0.5).clamp(0.12, 1.0);
      final h = math.max(3.0, size.height * level);
      final x = i * step + (step - w) / 2;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, (size.height - h) / 2, w, h), Radius.circular(w / 2)), (i + 0.5) / bars <= progress ? a : b);
    }
  }

  @override
  bool shouldRepaint(_WavePainter o) => o.progress != progress || o.seed != seed || o.played != played || o.rest != rest;
}

class _FileContent extends StatelessWidget {
  const _FileContent({required this.chat, required this.message, required this.color, required this.meta});
  final Chat chat;
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

  Widget _fileIcon() => Container(
    decoration: const BoxDecoration(color: Brand.lapis, shape: BoxShape.circle),
    child: Icon(_icon, color: Colors.white),
  );

  /// Downloads into "Paigham Documents" without opening it.
  Future<void> _download(BuildContext context) async {
    final key = message.filePath;
    if (key == null) return;
    final app = AppScope.read(context);
    await MediaCache.instance.bytes(key, () => app.fileUrl(key));
  }

  Future<void> _open(BuildContext context) async {
    if (message.filePath == null) return;
    final app = AppScope.read(context);
    final key = message.filePath!;
    final cache = MediaCache.instance;
    if (cache.persistent) {
      // like Telegram: downloaded once into "Paigham Documents", then opened
      // from the phone (also without internet)
      if (cache.filePath(key) == null) {
        // first tap: download (the ring shows it); open once it is here
        if (cache.isDownloading(key)) return;
        await cache.bytes(key, () => app.fileUrl(key));
        return;
      }
      final local = cache.filePath(key);
      if (local != null) {
        await OpenFilex.open(local);
        return;
      }
    }
    if (message.fileKey != null) {
      // encrypted: open the decrypted bytes, never the ciphertext link
      final b = await cache.bytes(key, () => app.fileUrl(key));
      if (b != null) await launchUrl(Uri.dataFromBytes(b, mimeType: message.mimeType ?? 'application/octet-stream'));
      return;
    }
    final url = await app.fileUrl(key);
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
            // Telegram: arrow → ring with X while it downloads → the file's icon
            SizedBox(
              width: 46,
              height: 46,
              child: message.pending
                  ? _SendingRing(size: 46, background: Brand.lapis, onCancel: () => AppScope.read(context).cancelSend(chat, message))
                  : message.filePath == null
                  ? _fileIcon()
                  : DownloadRing(cacheKey: message.filePath!, size: 46, background: Brand.lapis, onStart: () => _download(context), done: _fileIcon()),
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
                  _FileSizeLine(message: message, meta: meta),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1.2 MB", or "0.4 / 1.2 MB" while it downloads, or "uploading".
class _FileSizeLine extends StatelessWidget {
  const _FileSizeLine({required this.message, required this.meta});
  final Message message;
  final Color meta;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 12.5, color: meta);
    if (message.pending) return Text(context.tr('uploading'), style: style);
    final key = message.filePath;
    final total = message.fileSize;
    String sz(int? b) => '\u2066${localDigits(formatBytes(b), context.lang)}\u2069';
    if (key == null) return Text(sz(total), style: style);
    final cache = MediaCache.instance;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final p = cache.progressOf(key);
        if (p == null || total == null) return Text(sz(total), style: style);
        return ValueListenableBuilder<double>(
          valueListenable: p,
          builder: (_, v, _) => Text('${sz((v * total).round())} / ${sz(total)}', style: style),
        );
      },
    );
  }
}

/// Spinning ring with an X on a message that is still being sent; X cancels it.
class _SendingRing extends StatelessWidget {
  const _SendingRing({required this.onCancel, this.size = 48, this.background = Colors.black45});
  final VoidCallback onCancel;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onCancel,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.all(3),
            child: CircularProgressIndicator(strokeWidth: 2.6, strokeCap: StrokeCap.round, color: Colors.white),
          ),
          Icon(Icons.close_rounded, color: Colors.white, size: size * 0.5),
        ],
      ),
    ),
  );
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
