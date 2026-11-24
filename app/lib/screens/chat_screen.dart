import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../config.dart';
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
    _app!.sendText(chat, t);
    _focus.requestFocus();
  }

  void _toast(String key) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));

  Future<void> _attach(Chat chat, {required bool image}) async {
    final files = await FilePicker.pickFiles(type: image ? FileType.image : FileType.any);
    if (files.isEmpty) return;
    final f = files.first;
    final size = await f.length();
    if (size != null && size > AppConfig.maxFileBytes) {
      if (mounted) _toast('too_big');
      return;
    }
    final bytes = await f.readAsBytes();
    final caption = _input.text.trim();
    if (caption.isNotEmpty) _input.clear();
    final err = await _app!.sendFile(chat, name: f.name, bytes: bytes, caption: caption);
    if (err != null && mounted) _toast(err);
  }

  void _attachMenu(Chat chat) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachButton(icon: Icons.image_rounded, color: const Color(0xFF6A3FA0), label: ctx.tr('attach_photo'), onTap: () {
                Navigator.pop(ctx);
                _attach(chat, image: true);
              }),
              _AttachButton(icon: Icons.description_rounded, color: Brand.lapis, label: ctx.tr('attach_file'), onTap: () {
                Navigator.pop(ctx);
                _attach(chat, image: false);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addMember(Chat chat) async {
    final p = await showDialog<Profile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('add_member')),
        content: SizedBox(width: 420, child: PersonFinder(buttonKey: 'add', onFound: (p) => Navigator.pop(ctx, p))),
      ),
    );
    if (p == null || !mounted) return;
    await _app!.addMember(chat, p);
    if (mounted) _toast('added');
  }

  Future<void> _leave(Chat chat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: Text(d.tr('leave_q')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(d, true), child: Text(d.tr('leave'), style: const TextStyle(color: Brand.pomegranate))),
        ],
      ),
    );
    if (ok != true) return;
    await _app!.leaveChat(chat);
    if (mounted && !widget.embedded) Navigator.of(context).pop();
  }

  String _subtitle(AppController app, Chat c) {
    if (c.isGroup) return '${context.digits(c.members.length)} ${context.tr('members')}';
    final p = c.peer(app.myId ?? '');
    if (p == null) return '';
    return p.username != null ? '@${p.username}' : p.email;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final chat = app.chatById(widget.chatId);
    if (chat == null) return const Scaffold(body: SizedBox.shrink());
    final title = app.chatTitle(chat);
    final msgs = app.messagesOf(chat.id);
    final items = msgs == null ? null : _buildItems(app, chat, msgs);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        titleSpacing: widget.embedded ? 16 : 0,
        toolbarHeight: 62,
        title: Row(
          children: [
            Avatar(seed: chat.isGroup ? chat.id : (chat.peer(app.myId ?? '')?.id ?? chat.id), label: title, group: chat.isGroup, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(_subtitle(app, chat),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400, color: Color(0xCCFFFFFF))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!chat.isGroup) IconButton(onPressed: () => _toast('coming_soon'), icon: const Icon(Icons.call_outlined)),
          if (chat.isGroup)
            IconButton(onPressed: () => _addMember(chat), icon: const Icon(Icons.person_add_alt_1_outlined), tooltip: context.tr('add_member')),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'leave') _leave(chat);
            },
            itemBuilder: (ctx) => [PopupMenuItem(value: 'leave', child: Text(ctx.tr('leave_chat')))],
          ),
        ],
      ),
      body: GirihWallpaper(
        child: Column(
          children: [
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator())
                  : items.isEmpty
                      ? Center(child: SystemChip(text: context.tr('say_hello')))
                      : ListView.builder(
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          itemCount: items.length,
                          itemBuilder: (_, i) => items[items.length - 1 - i],
                        ),
            ),
            _composer(chat),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildItems(AppController app, Chat chat, List<Message> msgs) {
    final s = Strings(context.lang);
    final out = <Widget>[];
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      final prev = i > 0 ? msgs[i - 1] : null;
      final next = i < msgs.length - 1 ? msgs[i + 1] : null;
      if (prev == null || !sameDay(prev.createdAt, m.createdAt)) {
        out.add(SystemChip(text: dayHeader(m.createdAt, context.lang, s)));
      }
      bool joined(Message? a, Message b) =>
          a != null && a.senderId == b.senderId && sameDay(a.createdAt, b.createdAt) && b.createdAt.difference(a.createdAt).inMinutes.abs() < 5;
      out.add(MessageBubble(
        key: ValueKey(m.id),
        chat: chat,
        message: m,
        senderName: chat.isGroup && !joined(prev, m) ? (app.memberById(chat, m.senderId)?.name ?? '') : null,
        tail: !joined(m, next ?? m) || next == null,
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
                    const SizedBox(width: 14),
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
                          maxLength: 4000,
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
                      tooltip: context.tr('file'),
                      onPressed: () => _attachMenu(chat),
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
                tooltip: context.tr('type_message'),
                onPressed: _canSend ? () => _send(chat) : () => _attachMenu(chat),
                backgroundColor: Brand.saffron,
                shape: const CircleBorder(),
                child: Icon(_canSend ? Icons.send_rounded : Icons.add_rounded, color: Brand.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.icon, required this.color, required this.label, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            CircleAvatar(radius: 30, backgroundColor: color, child: Icon(icon, color: Colors.white, size: 28)),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}
