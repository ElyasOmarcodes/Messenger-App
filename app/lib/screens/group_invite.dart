import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

/// Opens a group invite link (paigham://join/<code or public name>):
/// shows the group and a Join button, like Telegram.
Future<void> openGroupInvite(BuildContext context, String code) async {
  final app = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  final nav = Navigator.of(context);
  final info = await app.inviteInfo(code);
  if (info == null) {
    messenger.showSnackBar(SnackBar(content: Text(app.s.get('invalid_link'))));
    return;
  }
  if (!context.mounted) return;
  final member = info['member'] == true;
  final go = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final avatar = info['avatar_path'] as String?;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Avatar(
                seed: info['chat_id'] as String,
                label: (info['title'] as String?) ?? '',
                imageUrl: avatar == null ? null : '$avatarBaseUrl/$avatar',
                size: 84,
              ),
              const SizedBox(height: 12),
              Text(
                (info['title'] as String?) ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(ctx.tr('n_members', {'n': ctx.digits('${info['members'] ?? 0}')}), style: TextStyle(color: cs.onSurfaceVariant)),
              if ((info['description'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Text(info['description'] as String, textAlign: TextAlign.center, style: const TextStyle(height: 1.5)),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(ctx.tr(member ? 'open_group' : 'join_group'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (go != true) return;
  final chat = await app.joinByInvite(code);
  if (chat == null) {
    messenger.showSnackBar(SnackBar(content: Text(app.s.get('invalid_link'))));
    return;
  }
  await nav.push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: chat.id)));
}
