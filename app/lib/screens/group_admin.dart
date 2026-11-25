import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';

/// Telegram-style group settings: name, description, what members may do,
/// invite links, public link, banned people, delete group.
class GroupEditScreen extends StatefulWidget {
  const GroupEditScreen({super.key, required this.chatId});
  final String chatId;

  @override
  State<GroupEditScreen> createState() => _GroupEditScreenState();
}

class _GroupEditScreenState extends State<GroupEditScreen> {
  late final TextEditingController _title, _about, _username;
  Map<String, bool> _perms = {};
  List<Map<String, dynamic>> _invites = [];
  List<Profile> _banned = [];
  bool _busy = false;

  Chat? get _chat => AppScope.read(context).chatById(widget.chatId);

  @override
  void initState() {
    super.initState();
    final c = AppScope.read(context).chatById(widget.chatId);
    _title = TextEditingController(text: c?.title ?? '');
    _about = TextEditingController(text: c?.description ?? '');
    _username = TextEditingController(text: c?.username ?? '');
    _perms = {
      for (final k in const ['send', 'media', 'add', 'pin', 'info']) k: (c?.permissions[k] as bool?) ?? const {'send', 'media', 'add'}.contains(k),
    };
    _loadLists();
  }

  Future<void> _loadLists() async {
    final app = AppScope.read(context);
    final c = _chat;
    if (c == null) return;
    final me = app.myId ?? '';
    final inv = c.can(me, 'invite') ? await app.invitesOf(c) : <Map<String, dynamic>>[];
    final ban = c.can(me, 'ban') ? await app.bannedOf(c) : <Profile>[];
    if (mounted) {
      setState(() {
        _invites = inv;
        _banned = ban;
      });
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _about.dispose();
    _username.dispose();
    super.dispose();
  }

  void _toast(String key) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final c = _chat;
    if (c == null) return;
    final me = app.myId ?? '';
    setState(() => _busy = true);
    String? err;
    if (c.can(me, 'info') && (_title.text.trim() != (c.title ?? '') || _about.text.trim() != (c.description ?? ''))) {
      err = await app.updateGroup(c, title: _title.text, description: _about.text);
    }
    if (err == null && c.can(me, 'ban')) {
      final now = {
        for (final k in _perms.keys) k: (c.permissions[k] as bool?) ?? const {'send', 'media', 'add'}.contains(k),
      };
      if (now.toString() != _perms.toString()) err = await app.setGroupPermissions(c, _perms);
    }
    if (err == null && c.members.any((m) => m.id == me && m.isOwner) && _username.text.trim() != (c.username ?? '')) {
      err = await app.setGroupUsername(c, _username.text.trim());
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return _toast(err);
    Navigator.of(context).pop();
  }

  Future<void> _newLink() async {
    final c = _chat;
    if (c == null) return;
    final link = await AppScope.read(context).createInvite(c);
    if (link == null) return _toast('err_generic');
    await Clipboard.setData(ClipboardData(text: link));
    _toast('link_copied');
    await _loadLists();
  }

  Future<void> _deleteGroup() async {
    final c = _chat;
    if (c == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(d.tr('delete_group')),
        content: Text(d.tr('delete_group_q')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(d.tr('delete'), style: const TextStyle(color: Brand.pomegranate)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nav = Navigator.of(context);
    final err = await AppScope.read(context).deleteGroup(c);
    if (err != null) return _toast(err);
    nav.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final c = app.chatById(widget.chatId);
    if (c == null) return const Scaffold();
    final me = app.myId ?? '';
    final owner = c.members.any((m) => m.id == me && m.isOwner);
    Widget section(String title, List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, bottom: 6),
            child: Text(
              title,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Column(children: children),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('edit_group')),
        actions: [
          IconButton(
            tooltip: context.tr('save'),
            onPressed: _busy ? null : _save,
            icon: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (c.can(me, 'info'))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  TextField(
                    controller: _title,
                    maxLength: 80,
                    decoration: InputDecoration(labelText: context.tr('group_name'), prefixIcon: const Icon(Icons.groups_rounded)),
                  ),
                  TextField(
                    controller: _about,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: context.tr('description'), prefixIcon: const Icon(Icons.info_outline_rounded)),
                  ),
                ],
              ),
            ),
          if (c.can(me, 'ban'))
            section(context.tr('perm_title'), [
              for (final (k, icon) in const [
                ('send', Icons.chat_rounded),
                ('media', Icons.photo_library_rounded),
                ('add', Icons.person_add_alt_1_rounded),
                ('pin', Icons.push_pin_rounded),
                ('info', Icons.edit_rounded),
              ])
                SwitchListTile(
                  secondary: Icon(icon),
                  title: Text(context.tr('perm_$k')),
                  value: _perms[k] ?? false,
                  onChanged: (v) => setState(() => _perms[k] = v),
                ),
            ]),
          if (c.can(me, 'invite'))
            section(context.tr('invite_link'), [
              for (final inv in _invites)
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: Text('paigham://join/${inv['code']}', textDirection: TextDirection.ltr, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(context.tr('n_members', {'n': context.digits('${inv['uses'] ?? 0}')})),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      final link = 'paigham://join/${inv['code']}';
                      switch (v) {
                        case 'copy':
                          await Clipboard.setData(ClipboardData(text: link));
                          _toast('link_copied');
                        case 'share':
                          await SharePlus.instance.share(ShareParams(text: link));
                        case 'revoke':
                          await app.revokeInvite(inv['code'] as String);
                          await _loadLists();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: 'copy', child: Text(ctx.tr('copy_link'))),
                      PopupMenuItem(value: 'share', child: Text(ctx.tr('share_link'))),
                      PopupMenuItem(
                        value: 'revoke',
                        child: Text(ctx.tr('revoke_link'), style: const TextStyle(color: Brand.pomegranate)),
                      ),
                    ],
                  ),
                ),
              ListTile(
                leading: Icon(Icons.add_link_rounded, color: cs.primary),
                title: Text(
                  context.tr('new_link'),
                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                ),
                onTap: _newLink,
              ),
            ]),
          if (owner)
            section(context.tr('public_link'), [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: TextField(
                  controller: _username,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(prefixText: 'paigham://join/', helperText: context.tr('public_link_hint'), helperMaxLines: 2),
                ),
              ),
            ]),
          if (c.can(me, 'ban') && _banned.isNotEmpty)
            section(context.tr('banned_users'), [
              for (final p in _banned)
                ListTile(
                  leading: Avatar(seed: p.id, label: p.name, imageUrl: p.avatarUrl, size: 40),
                  title: Text(p.name),
                  trailing: TextButton(
                    onPressed: () async {
                      final err = await app.unbanMember(c, p.id);
                      if (err != null) return _toast(err);
                      await _loadLists();
                    },
                    child: Text(context.tr('unban')),
                  ),
                ),
            ]),
          if (owner)
            section('', [
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded, color: Brand.pomegranate),
                title: Text(
                  context.tr('delete_group'),
                  style: const TextStyle(color: Brand.pomegranate, fontWeight: FontWeight.w600),
                ),
                onTap: _deleteGroup,
              ),
            ]),
        ],
      ),
    );
  }
}

/// Long-press / tap on a member (for admins): make admin, rights, dismiss, remove, ban.
Future<void> showMemberActions(BuildContext context, Chat chat, Profile m) async {
  final app = AppScope.read(context);
  final me = app.myId ?? '';
  Profile? mine;
  for (final x in chat.members) {
    if (x.id == me) mine = x;
  }
  if (mine == null || m.id == me || m.isOwner) return;
  final iOwner = mine.isOwner;
  final canPromote = iOwner || (mine.role == 'admin' && chat.can(me, 'add_admins') && m.role == 'member');
  final canRemove = chat.can(me, 'ban') && (m.role != 'admin' || iOwner);
  if (!canPromote && !canRemove) return;
  final messenger = ScaffoldMessenger.of(context);
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Avatar(seed: m.id, label: m.name, imageUrl: m.avatarUrl, size: 40),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(ctx.tr(m.role == 'admin' ? 'admin' : 'members')),
          ),
          const Divider(height: 1),
          if (canPromote && m.role != 'admin')
            ListTile(leading: const Icon(Icons.shield_rounded), title: Text(ctx.tr('make_admin')), onTap: () => Navigator.pop(ctx, 'admin')),
          if (canPromote && m.role == 'admin') ...[
            ListTile(leading: const Icon(Icons.tune_rounded), title: Text(ctx.tr('admin_rights')), onTap: () => Navigator.pop(ctx, 'admin')),
            ListTile(leading: const Icon(Icons.remove_moderator_rounded), title: Text(ctx.tr('dismiss_admin')), onTap: () => Navigator.pop(ctx, 'dismiss')),
          ],
          if (canRemove) ...[
            ListTile(
              leading: const Icon(Icons.person_remove_rounded, color: Brand.pomegranate),
              title: Text(ctx.tr('remove_member'), style: const TextStyle(color: Brand.pomegranate)),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            ListTile(
              leading: const Icon(Icons.block_rounded, color: Brand.pomegranate),
              title: Text(ctx.tr('ban_member'), style: const TextStyle(color: Brand.pomegranate)),
              onTap: () => Navigator.pop(ctx, 'ban'),
            ),
          ],
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  String? err;
  switch (choice) {
    case 'admin':
      final rights = await _askRights(context, m);
      if (rights == null) return;
      err = await app.setMemberRole(chat, m.id, admin: true, rights: rights);
    case 'dismiss':
      err = await app.setMemberRole(chat, m.id, admin: false);
    case 'remove':
      err = await app.removeMember(chat, m.id);
    case 'ban':
      err = await app.removeMember(chat, m.id, ban: true);
  }
  if (err != null) messenger.showSnackBar(SnackBar(content: Text(app.s.get(err))));
}

Future<Map<String, bool>?> _askRights(BuildContext context, Profile m) {
  const keys = ['info', 'delete', 'ban', 'invite', 'pin', 'add', 'add_admins'];
  final rights = {for (final k in keys) k: (m.rights?[k] as bool?) ?? k != 'add_admins'};
  return showModalBottomSheet<Map<String, bool>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ctx.tr('admin_rights'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final k in keys)
              SwitchListTile(
                title: Text(
                  ctx.tr(switch (k) {
                    'info' => 'perm_info',
                    'pin' => 'perm_pin',
                    'add' => 'perm_add',
                    _ => 'right_$k',
                  }),
                ),
                value: rights[k]!,
                onChanged: (v) => set(() => rights[k] = v),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(onPressed: () => Navigator.pop(ctx, rights), child: Text(ctx.tr('save'))),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
