import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import 'avatar.dart';

/// The right picture for any chat: Saved Messages, a group, or a person.
class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.chat, this.size = 52});
  final Chat chat;
  final double size;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (chat.isSaved) return SavedAvatar(size: size);
    final peer = chat.isGroup ? null : chat.peer(app.myId ?? '');
    final avatar = Avatar(
      seed: chat.isGroup ? chat.id : (peer?.id ?? chat.id),
      label: app.chatTitle(chat),
      group: chat.isGroup,
      imageUrl: chat.isGroup ? chat.avatarUrl : peer?.avatarUrl,
      size: size,
    );
    if (peer == null || !peer.online || size < 36) return avatar;
    // online: a green dot at the corner, like Telegram / WhatsApp
    final dot = size * 0.26;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          PositionedDirectional(
            end: size * 0.02,
            bottom: size * 0.02,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759),
                shape: BoxShape.circle,
                border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: size * 0.045),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String key) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(context.tr(key)), duration: const Duration(seconds: 2)));

Future<bool> _confirm(BuildContext context, String questionKey, String actionKey) async =>
    await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (d) => CupertinoAlertDialog(
        content: Text(d.tr(questionKey), style: const TextStyle(fontSize: 15)),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(d, true), child: Text(d.tr(actionKey))),
        ],
      ),
    ) ??
    false;

/// Archives with an "Undo" in the snackbar (also used by swipe).
Future<void> archiveChat(BuildContext context, Chat chat) async {
  final app = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final undo = context.tr('undo');
  final text = context.tr('chat_archived');
  await app.setArchived(chat, true);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        action: SnackBarAction(label: undo, textColor: Brand.blueBright, onPressed: () => app.setArchived(chat, false)),
      ),
    );
}

Future<void> clearHistoryFlow(BuildContext context, Chat chat) async {
  if (!await _confirm(context, 'clear_history_q', 'clear')) return;
  if (!context.mounted) return;
  await AppScope.read(context).clearHistory(chat);
  if (context.mounted) _toast(context, 'history_cleared');
}

/// Returns true when the chat is gone (so a chat page can close itself).
Future<bool> deleteChatFlow(BuildContext context, Chat chat) async {
  if (!await _confirm(context, chat.isGroup ? 'leave_q' : 'delete_chat_q', chat.isGroup ? 'leave' : 'delete')) return false;
  if (!context.mounted) return false;
  await AppScope.read(context).leaveChat(chat);
  return true;
}

/// Telegram-style options for a chat in the list (long-press or right-click).
Future<void> showChatOptions(BuildContext context, Chat chat) async {
  final app = AppScope.read(context);
  final unreadNow = chat.unread > 0 || chat.markedUnread;
  final items = <(IconData, String, bool, Future<void> Function())>[
    (
      chat.pinnedAt == null ? Icons.push_pin_outlined : Icons.push_pin_rounded,
      chat.pinnedAt == null ? 'pin_chat' : 'unpin_chat',
      false,
      () async {
        if (!await app.togglePinChat(chat) && context.mounted) _toast(context, 'pin_limit');
      },
    ),
    if (!chat.isSaved)
      (
        chat.muted ? Icons.notifications_active_outlined : Icons.notifications_off_outlined,
        chat.muted ? 'unmute_chat' : 'mute_chat',
        false,
        () => app.toggleMute(chat),
      ),
    if (!chat.isSaved)
      (
        unreadNow ? Icons.mark_chat_read_outlined : Icons.mark_chat_unread_outlined,
        unreadNow ? 'mark_read' : 'mark_unread',
        false,
        () => app.toggleUnread(chat),
      ),
    (
      chat.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
      chat.archived ? 'unarchive' : 'archive',
      false,
      () async {
        if (chat.archived) {
          await app.setArchived(chat, false);
        } else if (context.mounted) {
          await archiveChat(context, chat);
        }
      },
    ),
    (Icons.cleaning_services_outlined, 'clear_history', true, () => clearHistoryFlow(context, chat)),
    if (!chat.isSaved) (Icons.delete_outline_rounded, chat.isGroup ? 'leave_chat' : 'delete_chat', true, () => deleteChatFlow(context, chat)),
  ];
  final picked = await showModalBottomSheet<Future<void> Function()>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  ChatAvatar(chat: chat, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.chatTitle(chat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        if (chat.muted || chat.pinnedAt != null || chat.archived)
                          Row(
                            children: [
                              if (chat.pinnedAt != null) Icon(Icons.push_pin_rounded, size: 14, color: cs.onSurfaceVariant),
                              if (chat.muted) Icon(Icons.volume_off_rounded, size: 14, color: cs.onSurfaceVariant),
                              if (chat.archived) Icon(Icons.archive_rounded, size: 14, color: cs.onSurfaceVariant),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            for (final (icon, key, danger, action) in items)
              ListTile(
                leading: Icon(icon, color: danger ? Brand.pomegranate : cs.onSurfaceVariant),
                title: Text(
                  ctx.tr(key),
                  style: TextStyle(fontWeight: FontWeight.w600, color: danger ? Brand.pomegranate : null),
                ),
                onTap: () => Navigator.pop(ctx, action),
              ),
            const SizedBox(height: 6),
          ],
        ),
      );
    },
  );
  await picked?.call();
}
