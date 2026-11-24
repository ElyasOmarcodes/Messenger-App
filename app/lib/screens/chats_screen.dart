import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.onOpen, this.selectedId});
  final void Function(Chat) onOpen;
  final String? selectedId;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final q = _query.trim().toLowerCase();
    final list = app.sortedChats.where((c) {
      if (q.isEmpty) return true;
      if (app.chatTitle(c).toLowerCase().contains(q)) return true;
      return app.messagesOf(c.id).any((m) => app.display(m.text).toLowerCase().contains(q));
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: context.tr('search'),
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text(context.tr('no_results')))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: list.length,
                  itemBuilder: (_, i) => ChatTile(
                    chat: list[i],
                    selected: list[i].id == widget.selectedId,
                    onTap: () => widget.onOpen(list[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class ChatTile extends StatelessWidget {
  const ChatTile({super.key, required this.chat, required this.onTap, this.selected = false});
  final Chat chat;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final last = app.lastMessage(chat.id);
    final title = app.chatTitle(chat);
    final s = Strings(context.lang);

    String preview;
    if (last == null) {
      preview = context.tr('no_messages');
    } else {
      final body = app.display(last.text).replaceAll('\n', ' ');
      final who = last.outgoing
          ? '${context.tr('you')}: '
          : ((chat.kind == ChatKind.group || chat.kind == ChatKind.lobby) && !last.system && last.senderName.isNotEmpty)
              ? '${last.senderName}: '
              : '';
      preview = '$who$body';
    }

    return Material(
      color: selected ? cs.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: () => _actions(context, app),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Avatar(seed: chat.peerId ?? chat.groupId ?? chat.id, label: title, kind: chat.kind, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (chat.kind == ChatKind.channel || chat.kind == ChatKind.bot) ...[
                          const SizedBox(width: 4),
                          Icon(
                            chat.kind == ChatKind.channel ? Icons.verified_rounded : Icons.smart_toy_outlined,
                            size: 16,
                            color: chat.kind == ChatKind.channel ? Brand.saffronDeep : cs.onSurfaceVariant,
                          ),
                        ],
                        const Spacer(),
                        if (last != null)
                          Text(
                            chatListTime(last.time, context.lang, s),
                            style: TextStyle(
                              fontSize: 12,
                              color: chat.unread > 0 ? Brand.saffronDeep : cs.onSurfaceVariant,
                              fontWeight: chat.unread > 0 ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (last != null && last.outgoing) ...[
                          Icon(
                            last.status == MsgStatus.read || last.status == MsgStatus.delivered
                                ? Icons.done_all_rounded
                                : (last.status == MsgStatus.failed ? Icons.error_outline_rounded : Icons.done_rounded),
                            size: 16,
                            color: last.status == MsgStatus.read
                                ? Brand.saffronDeep
                                : (last.status == MsgStatus.failed ? Brand.pomegranate : cs.onSurfaceVariant),
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
                          ),
                        ),
                        if (chat.pinned && chat.unread == 0)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 6),
                            child: Icon(Icons.push_pin_rounded, size: 16, color: cs.onSurfaceVariant),
                          ),
                        if (chat.unread > 0)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 22),
                            decoration: BoxDecoration(
                              color: chat.kind == ChatKind.lobby ? cs.onSurfaceVariant.withValues(alpha: 0.5) : Brand.saffron,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              context.digits(chat.unread),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Brand.ink),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _actions(BuildContext context, AppController app) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(chat.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded),
              title: Text(ctx.tr(chat.pinned ? 'unpin' : 'pin')),
              onTap: () {
                app.togglePin(chat);
                Navigator.pop(ctx);
              },
            ),
            if (chat.kind == ChatKind.direct || chat.kind == ChatKind.group)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Brand.pomegranate),
                title: Text(ctx.tr('delete_chat'), style: const TextStyle(color: Brand.pomegranate)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      content: Text(d.tr('delete_chat_q')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
                        TextButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: Text(d.tr('delete'), style: const TextStyle(color: Brand.pomegranate)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) app.deleteChat(chat);
                },
              ),
          ],
        ),
      ),
    );
  }
}
