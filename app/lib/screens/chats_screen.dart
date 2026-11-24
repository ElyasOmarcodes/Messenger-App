import 'package:flutter/material.dart';

import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';

enum _Filter { all, personal, groups, unread }

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, required this.onOpen, this.selectedId});
  final void Function(Chat) onOpen;
  final String? selectedId;

  /// Kept for older callers; the search field is always visible now.
  static void focusSearch(BuildContext context) {}

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final list = app.chats.where((c) {
      switch (_filter) {
        case _Filter.personal:
          if (c.isGroup) return false;
        case _Filter.groups:
          if (!c.isGroup) return false;
        case _Filter.unread:
          if (c.unread == 0) return false;
        case _Filter.all:
          break;
      }
      if (q.isEmpty) return true;
      if (app.chatTitle(c).toLowerCase().contains(q)) return true;
      return c.members.any((m) => m.email.contains(q) || (m.username ?? '').contains(q));
    }).toList();

    final groupsUnread = app.chats.where((c) => c.isGroup).fold<int>(0, (n, c) => n + c.unread);
    final personalUnread = app.totalUnread - groupsUnread;

    return RefreshIndicator(
      onRefresh: app.reloadChats,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: context.tr('search'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surfaceContainerLow,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _chip(context, _Filter.all, 'all', app.totalUnread),
                  _chip(context, _Filter.personal, 'personal', personalUnread),
                  _chip(context, _Filter.groups, 'groups', groupsUnread),
                  _chip(context, _Filter.unread, 'unread', 0),
                ],
              ),
            ),
          ),
          if (!app.chatsLoaded)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(Icons.forum_rounded, size: 48, color: cs.primary),
                    ),
                    const SizedBox(height: 16),
                    Text(context.tr(q.isEmpty ? 'no_chats' : 'no_results'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (q.isEmpty && _filter == _Filter.all)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(context.tr('no_chats_sub'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 110),
              sliver: SliverList.builder(
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

  Widget _chip(BuildContext context, _Filter f, String key, int count) {
    final cs = Theme.of(context).colorScheme;
    final sel = _filter == f;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      child: ChoiceChip(
        selected: sel,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = f),
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(context.tr(key), style: TextStyle(color: sel ? cs.primary : cs.onSurface, fontWeight: FontWeight.w700)),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: sel ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(10)),
              child: Text(context.digits(count), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
          ],
        ]),
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
    final peer = chat.isGroup ? null : chat.peer(app.myId ?? '');

    String preview;
    String who = '';
    if (last == null) {
      preview = context.tr('no_messages');
    } else {
      who = mine ? '${context.tr('you')}: ' : (chat.isGroup ? '${app.memberById(chat, last.senderId)?.name ?? ''}: ' : '');
      preview = app.previewOf(last).replaceAll('\n', ' ');
    }
    final read = last != null && mine && app.statusOf(chat, last) == MsgStatus.read;

    return Material(
      color: selected ? cs.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 14, 8),
          child: Row(
            children: [
              Avatar(
                seed: chat.isGroup ? chat.id : (peer?.id ?? chat.id),
                label: title,
                group: chat.isGroup,
                imageUrl: peer?.avatarUrl,
                size: 58,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (chat.isGroup) Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: Icon(Icons.groups_rounded, size: 17, color: cs.onSurface)),
                      Expanded(
                        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
                      ),
                      if (mine) ...[
                        Icon(read ? Icons.done_all_rounded : Icons.done_rounded, size: 17, color: cs.primary),
                        const SizedBox(width: 3),
                      ],
                      if (last != null)
                        Text(chatListTime(last.createdAt, context.lang, s),
                            style: TextStyle(fontSize: 12.5, color: chat.unread > 0 ? cs.primary : cs.onSurfaceVariant)),
                    ]),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            if (who.isNotEmpty) TextSpan(text: who, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600)),
                            TextSpan(text: preview),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5, color: cs.onSurfaceVariant),
                        ),
                      ),
                      if (chat.unread > 0)
                        Container(
                          margin: const EdgeInsetsDirectional.only(start: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          constraints: const BoxConstraints(minWidth: 24),
                          decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                          child: Text(context.digits(chat.unread),
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                    ]),
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
