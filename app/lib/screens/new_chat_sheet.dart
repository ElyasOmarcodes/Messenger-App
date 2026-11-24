import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';

/// Bottom sheet: show my ID, start a direct chat, create or join a group.
Future<Chat?> showNewChatSheet(BuildContext context) {
  return showModalBottomSheet<Chat>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => const _NewChatSheet(),
  );
}

class _NewChatSheet extends StatelessWidget {
  const _NewChatSheet();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final id = app.profile!.id;

    Future<void> run(Future<Chat?> Function() f) async {
      final nav = Navigator.of(context);
      final chat = await f();
      if (chat != null) nav.pop(chat);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('new_chat'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            MyIdCard(id: id),
            const SizedBox(height: 12),
            _Option(
              icon: Icons.person_add_alt_1_rounded,
              color: cs.primary,
              title: context.tr('chat_with_id'),
              onTap: () => run(() => _directDialog(context, app)),
            ),
            _Option(
              icon: Icons.group_add_rounded,
              color: const Color(0xFF1E8C6E),
              title: context.tr('new_group'),
              onTap: () => run(() async {
                final c = await _groupDialog(context, app);
                if (c != null && context.mounted) await showInviteDialog(context, c.groupId!);
                return c;
              }),
            ),
            _Option(
              icon: Icons.login_rounded,
              color: Brand.saffronDeep,
              title: context.tr('join_group'),
              onTap: () => run(() => _joinDialog(context, app)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.icon, required this.color, required this.title, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}

/// Card with the user's ID, a copy button and a QR button.
class MyIdCard extends StatelessWidget {
  const MyIdCard({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('your_id'), style: TextStyle(fontSize: 12.5, color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    prettyId(id),
                    style: TextStyle(fontSize: 22, letterSpacing: 1.5, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer),
                  ),
                ),
                Text(context.tr('share_id_hint'), style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer.withValues(alpha: 0.75))),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: prettyId(id)));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
            },
            icon: Icon(Icons.copy_rounded, color: cs.onPrimaryContainer),
          ),
          IconButton(
            tooltip: context.tr('show_qr'),
            onPressed: () => showQrDialog(context, 'paigham:u:$id', prettyId(id)),
            icon: Icon(Icons.qr_code_2_rounded, color: cs.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}

Future<void> showQrDialog(BuildContext context, String data, String caption) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: QrImageView(
              data: data,
              size: 220,
              eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Brand.lapis),
              dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Brand.lapisDeep),
            ),
          ),
          const SizedBox(height: 12),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(caption, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
          ),
        ],
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
    ),
  );
}

Future<void> showInviteDialog(BuildContext context, String groupId) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('invite_code')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ctx.tr('invite_hint')),
          const SizedBox(height: 14),
          Directionality(
            textDirection: TextDirection.ltr,
            child: SelectableText(prettyId(groupId), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => showQrDialog(ctx, 'paigham:g:$groupId', prettyId(groupId)),
          child: Text(ctx.tr('show_qr')),
        ),
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: prettyId(groupId)));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
          },
          child: Text(ctx.tr('copy')),
        ),
      ],
    ),
  );
}

Future<Chat?> _directDialog(BuildContext context, AppController app) async {
  final id = TextEditingController();
  final name = TextEditingController();
  String? error;
  final result = await showDialog<Chat>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(ctx.tr('chat_with_id')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: id,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(labelText: ctx.tr('friend_id'), hintText: 'XXXXX-XXXXX', errorText: error),
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: InputDecoration(labelText: ctx.tr('friend_name'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 44)),
            onPressed: () {
              final v = normalizeId(id.text);
              if (!isValidUserId(v)) return setState(() => error = ctx.tr('invalid_id'));
              if (v == app.profile!.id) return setState(() => error = ctx.tr('own_id'));
              Navigator.pop(ctx, app.startDirect(v, name: name.text));
            },
            child: Text(ctx.tr('start_chat')),
          ),
        ],
      ),
    ),
  );
  return result;
}

Future<Chat?> _groupDialog(BuildContext context, AppController app) async {
  final name = TextEditingController();
  return showDialog<Chat>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('new_group')),
      content: TextField(
        controller: name,
        autofocus: true,
        maxLength: 50,
        decoration: InputDecoration(labelText: ctx.tr('group_name'), counterText: ''),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(80, 44)),
          onPressed: () {
            if (name.text.trim().isEmpty) return;
            Navigator.pop(ctx, app.createGroup(name.text));
          },
          child: Text(ctx.tr('create')),
        ),
      ],
    ),
  );
}

Future<Chat?> _joinDialog(BuildContext context, AppController app) async {
  final code = TextEditingController();
  String? error;
  return showDialog<Chat>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(ctx.tr('join_group')),
        content: Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: ctx.tr('group_code'), hintText: 'XXXXX-XXXXX', errorText: error),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(80, 44)),
            onPressed: () async {
              final v = normalizeId(code.text);
              if (!isValidUserId(v)) return setState(() => error = ctx.tr('invalid_id'));
              final c = await app.joinGroup(v);
              if (ctx.mounted) Navigator.pop(ctx, c);
            },
            child: Text(ctx.tr('join')),
          ),
        ],
      ),
    ),
  );
}
