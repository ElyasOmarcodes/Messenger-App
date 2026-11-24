import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';
import 'new_chat_sheet.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.embedded = false});
  final String chatId;

  /// True when shown as the right-hand pane on wide screens.
  final bool embedded;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  AppController? _app;
  bool _canSend = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app == null) {
      _app = AppScope.read(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => _app!.openChat(widget.chatId));
    }
  }

  @override
  void dispose() {
    _app?.closeChat(widget.chatId);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send(Chat chat) {
    final t = _input.text;
    if (t.trim().isEmpty) return;
    _input.clear();
    setState(() => _canSend = false);
    _app!.send(chat, t);
    _focus.requestFocus();
  }

  void _soon() => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('coming_soon'))));

  String _subtitle(Chat c) => switch (c.kind) {
        ChatKind.direct => 'ID: ${prettyId(c.peerId!)}',
        ChatKind.group => '${context.tr('group')} · ${prettyId(c.groupId!)}',
        ChatKind.lobby => context.tr('lobby_sub'),
        ChatKind.bot => context.tr('assistant_sub'),
        ChatKind.channel => context.tr('news_sub'),
        ChatKind.saved => context.tr('saved_sub'),
      };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final chat = app.chatById(widget.chatId);
    if (chat == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final title = app.chatTitle(chat);
    final items = _buildItems(app, chat);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        toolbarHeight: 62,
        title: Row(
          children: [
            Avatar(seed: chat.peerId ?? chat.groupId ?? chat.id, label: title, kind: chat.kind, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(
                    _subtitle(chat),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: Color(0xCCFFFFFF)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (chat.kind == ChatKind.direct) ...[
            IconButton(onPressed: _soon, icon: const Icon(Icons.videocam_outlined)),
            IconButton(onPressed: _soon, icon: const Icon(Icons.call_outlined)),
          ],
          if (chat.kind == ChatKind.group)
            IconButton(
              onPressed: () => showInviteDialog(context, chat.groupId!),
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: context.tr('invite_code'),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pin') app.togglePin(chat);
              if (v == 'copy' && chat.peerId != null) {
                Clipboard.setData(ClipboardData(text: prettyId(chat.peerId!)));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'pin', child: Text(ctx.tr(chat.pinned ? 'unpin' : 'pin'))),
              if (chat.peerId != null) PopupMenuItem(value: 'copy', child: Text('${ctx.tr('copy')} ID')),
            ],
          ),
        ],
      ),
      body: GirihWallpaper(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                itemCount: items.length,
                itemBuilder: (_, i) => items[items.length - 1 - i],
              ),
            ),
            if (chat.canWrite) _composer(chat) else _readOnlyBar(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItems(AppController app, Chat chat) {
    final msgs = app.messagesOf(chat.id);
    final s = Strings(context.lang);
    final out = <Widget>[];
    if (chat.kind == ChatKind.direct || chat.kind == ChatKind.group || chat.kind == ChatKind.lobby) {
      out.add(_Notice(text: context.tr('encryption_note')));
    }
    final isGroup = chat.kind == ChatKind.group || chat.kind == ChatKind.lobby;
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final prev = i > 0 ? msgs[i - 1] : null;
      final next = i < msgs.length - 1 ? msgs[i + 1] : null;
      if (prev == null || !sameDay(prev.time, m.time)) {
        out.add(SystemChip(text: dayHeader(m.time, context.lang, s)));
      }
      bool joined(Message? a, Message b) =>
          a != null &&
          !a.system &&
          a.senderId == b.senderId &&
          a.outgoing == b.outgoing &&
          sameDay(a.time, b.time) &&
          b.time.difference(a.time).inMinutes.abs() < 5;
      final firstOfRun = !joined(prev, m);
      final lastOfRun = next == null || !joined(m, next) || !sameDay(m.time, next.time);
      out.add(MessageBubble(
        key: ValueKey(m.id),
        message: m,
        showSender: isGroup && firstOfRun,
        tail: lastOfRun,
      ));
    }
    return out;
  }

  Widget _composer(Chat chat) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: dark ? Brand.nightRaised : Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: _soon,
                      icon: Icon(Icons.emoji_emotions_outlined, color: cs.onSurfaceVariant),
                    ),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter): () => _send(chat),
                          const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _send(chat),
                        },
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 2000,
                          textInputAction: TextInputAction.newline,
                          keyboardType: TextInputType.multiline,
                          onChanged: (v) {
                            final can = v.trim().isNotEmpty;
                            if (can != _canSend) setState(() => _canSend = can);
                          },
                          decoration: InputDecoration(
                            hintText: context.tr('type_message'),
                            counterText: '',
                            filled: false,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _soon,
                      icon: Icon(Icons.attach_file_rounded, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 50,
              height: 50,
              child: FloatingActionButton(
                heroTag: null,
                elevation: 1,
                onPressed: _canSend ? () => _send(chat) : _soon,
                backgroundColor: Brand.saffron,
                shape: const CircleBorder(),
                child: Icon(_canSend ? Icons.send_rounded : Icons.mic_rounded, color: Brand.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyBar() {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        color: cs.surface,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PaighamLogo(size: 22, background: false),
            const SizedBox(width: 8),
            Text(context.tr('channel_readonly'), style: TextStyle(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF3A2E10) : Brand.saffronMist,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open_rounded, size: 16, color: Brand.saffronDeep),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: dark ? const Color(0xFFF5D58A) : const Color(0xFF6B4A00)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
