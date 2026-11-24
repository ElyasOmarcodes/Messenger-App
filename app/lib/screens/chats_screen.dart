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
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final list = app.chats.where((c) {
      if (q.isEmpty) return true;
      if (app.chatTitle(c).toLowerCase().contains(q)) return true;
      return c.members.any((m) => m.email.contains(q) || (m.username ?? '').contains(q));
    }).toList();

    return RefreshIndicator(
      onRefresh: app.reloadChats,
      child: Column(
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
            child: !app.chatsLoaded
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 80),
                        Icon(Icons.forum_outlined, size: 64, color: cs.primary.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(context.tr(q.isEmpty ? 'no_chats' : 'no_results'),
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        if (q.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(context.tr('no_chats_sub'),
                                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                          ),
                      ])
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
      ),
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
    final last = chat.lastMessage;
    final title = app.chatTitle(chat);
    final s = Strings(context.lang);
    final mine = last != null && last.senderId == app.myId;

    String preview;
    if (last == null) {
      preview = context.tr('no_messages');
    } else {
      final who = mine
          ? '${context.tr('you')}: '
          : chat.isGroup
              ? '${app.memberById(chat, last.senderId)?.name ?? ''}: '
              : '';
      preview = '$who${app.previewOf(last).replaceAll('\n', ' ')}';
    }
    final read = last != null && mine && app.statusOf(chat, last) == MsgStatus.read;

    return Material(
      color: selected ? cs.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Avatar(seed: chat.isGroup ? chat.id : (chat.peer(app.myId ?? '')?.id ?? chat.id), label: title, group: chat.isGroup, size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                        if (last != null)
                          Text(
                            chatListTime(last.createdAt, context.lang, s),
                            style: TextStyle(
                              fontSize: 12,
                              color: chat.unread > 0 ? Brand.accentDeep : cs.onSurfaceVariant,
                              fontWeight: chat.unread > 0 ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (mine) ...[
                          Icon(read ? Icons.done_all_rounded : Icons.done_rounded,
                              size: 16, color: read ? Brand.accentDeep : cs.onSurfaceVariant),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(preview,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
                        ),
                        if (chat.unread > 0)
                          Container(
                            margin: const EdgeInsetsDirectional.only(start: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            constraints: const BoxConstraints(minWidth: 22),
                            decoration: BoxDecoration(color: Brand.accent, borderRadius: BorderRadius.circular(12)),
                            child: Text(context.digits(chat.unread),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
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
}
