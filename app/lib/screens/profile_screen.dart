import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import '../widgets/media_views.dart';
import 'call_screen.dart';
import 'chat_screen.dart';
import 'new_chat_sheet.dart';

enum _Kind { me, user, group }

/// Telegram-style profile page: big photo, name, action buttons, details,
/// and the photos and files shared in the chat.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen.me({super.key})
      : _kind = _Kind.me,
        profile = null,
        chatId = null;
  const ProfileScreen.user({super.key, required this.profile, this.chatId}) : _kind = _Kind.user;
  const ProfileScreen.group({super.key, required this.chatId})
      : _kind = _Kind.group,
        profile = null;

  final _Kind _kind;
  final Profile? profile;
  final String? chatId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0; // 0 media, 1 files

  void _toast(String key) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(key))));

  Future<void> _changePhoto(AppController app) async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final f = files.first;
    final size = await f.length();
    if (size != null && size > 5 * 1024 * 1024) return _toast('photo_too_big');
    final bytes = await f.readAsBytes();
    final chat = widget._kind == _Kind.group ? app.chatById(widget.chatId!) : null;
    final ok = chat != null ? await app.setGroupPhoto(chat, f.name, bytes) : await app.uploadAvatar(f.name, bytes);
    if (!ok && mounted) _toast('err_generic');
  }

  Future<void> _edit(String titleKey, String initial, Future<bool> Function(String) save,
      {String? hint, bool ltr = false, String errorKey = 'err_generic'}) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(titleKey)),
        content: Directionality(
          textDirection: ltr ? TextDirection.ltr : Directionality.of(ctx),
          child: TextField(controller: c, autofocus: true, maxLength: 40, decoration: InputDecoration(helperText: hint, helperMaxLines: 2)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    if (v == null) return;
    if (!await save(v) && mounted) _toast(errorKey);
  }

  Future<Chat?> _directChat(AppController app, Profile p) async {
    if (widget.chatId != null) return app.chatById(widget.chatId!);
    return app.startDirectChat(p);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;

    late final String title, subtitle, seed;
    String? photo;
    bool group = false;
    Chat? chat = widget.chatId == null ? null : app.chatById(widget.chatId!);
    switch (widget._kind) {
      case _Kind.me:
        final me = app.me;
        title = me?.name ?? '';
        subtitle = me?.username != null ? '@${me!.username}' : app.myEmail;
        seed = app.myId ?? '';
        photo = me?.avatarUrl;
      case _Kind.user:
        final p = (chat == null ? null : app.memberById(chat, widget.profile!.id)) ?? widget.profile!;
        title = p.name;
        subtitle = p.username != null ? '@${p.username}' : p.email;
        seed = p.id;
        photo = p.avatarUrl;
      case _Kind.group:
        title = chat == null ? '' : app.chatTitle(chat);
        subtitle = '${context.digits(chat?.members.length ?? 0)} ${context.tr('members')}';
        seed = widget.chatId!;
        group = true;
        photo = chat?.avatarUrl;
    }

    return Scaffold(
      appBar: widget._kind == _Kind.me
          ? null
          : AppBar(title: Text(context.tr(widget._kind == _Kind.group ? 'group_info' : 'info'))),
      body: ListView(
        padding: EdgeInsets.only(top: widget._kind == _Kind.me ? MediaQuery.paddingOf(context).top + 12 : 8, bottom: 110),
        children: [
          // ── Header ──
          Center(
            child: GestureDetector(
              onTap: widget._kind != _Kind.user ? () => _changePhoto(app) : null,
              child: Stack(children: [
                Avatar(seed: seed, label: title, imageUrl: photo, group: group, size: 112),
                if (widget._kind != _Kind.user)
                  PositionedDirectional(
                    bottom: 2,
                    end: 2,
                    child: Semantics(
                      button: true,
                      label: context.tr('change_photo'),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle, border: Border.all(color: cs.surface, width: 3)),
                        child: const Icon(Icons.photo_camera_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
          ),
          const SizedBox(height: 18),

          // ── Action buttons ──
          if (widget._kind == _Kind.user)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _Action(icon: Icons.chat_bubble_rounded, label: context.tr('message'), onTap: () async {
                  final c = await _directChat(app, widget.profile!);
                  if (c == null || !context.mounted) return;
                  if (widget.chatId != null) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
                  }
                }),
                _Action(icon: Icons.call_rounded, label: context.tr('voice_call'), onTap: () async {
                  final c = await _directChat(app, widget.profile!);
                  if (c != null && context.mounted) CallScope.read(context).call(c, withVideo: false);
                }),
                _Action(icon: Icons.videocam_rounded, label: context.tr('video_call'), onTap: () async {
                  final c = await _directChat(app, widget.profile!);
                  if (c != null && context.mounted) CallScope.read(context).call(c, withVideo: true);
                }),
              ]),
            ),
          if (widget._kind == _Kind.me)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _Action(icon: Icons.add_a_photo_rounded, label: context.tr('change_photo'), onTap: () => _changePhoto(app)),
                _Action(
                  icon: Icons.edit_rounded,
                  label: context.tr('edit_name'),
                  onTap: () => _edit('edit_name', app.me?.displayName ?? '', (v) => app.updateProfile(displayName: v)),
                ),
                _Action(icon: Icons.bookmark_rounded, label: context.tr('saved_short'), onTap: () => openSavedMessages(context)),
              ]),
            ),
          if (widget._kind == _Kind.group && chat != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _Action(icon: Icons.person_add_alt_1_rounded, label: context.tr('add_member'), onTap: () async {
                  final p = await showDialog<Profile>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(ctx.tr('add_member')),
                      content: SizedBox(width: 420, child: PersonFinder(buttonKey: 'add', onFound: (p) => Navigator.pop(ctx, p))),
                    ),
                  );
                  if (p != null) await app.addMember(chat, p);
                }),
                _Action(icon: Icons.logout_rounded, label: context.tr('leave'), danger: true, onTap: () async {
                  await app.leaveChat(chat);
                  if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                }),
              ]),
            ),
          const SizedBox(height: 14),

          // ── Details ──
          _Section(children: [
            if (widget._kind == _Kind.me) ...[
              _Info(icon: Icons.alternate_email_rounded, value: app.myEmail, label: context.tr('email'), ltr: true),
              _Info(
                icon: Icons.tag_rounded,
                value: app.me?.username != null ? '@${app.me!.username}' : context.tr('not_set'),
                label: context.tr('username'),
                ltr: app.me?.username != null,
                onTap: () => _edit('username', app.me?.username ?? '', (v) => app.updateProfile(username: v),
                    hint: context.tr('username_hint'), ltr: true, errorKey: 'username_taken'),
              ),
            ],
            if (widget._kind == _Kind.user) ...[
              _Info(icon: Icons.alternate_email_rounded, value: widget.profile!.email, label: context.tr('email'), ltr: true),
              if (widget.profile!.username != null)
                _Info(icon: Icons.tag_rounded, value: '@${widget.profile!.username}', label: context.tr('username'), ltr: true),
            ],
            if (widget._kind == _Kind.group && chat != null)
              for (final m in chat.members)
                ListTile(
                  leading: Avatar(seed: m.id, label: m.name, imageUrl: m.avatarUrl, size: 42),
                  title: Text(m.id == app.myId ? '${m.name} (${context.tr('you')})' : m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(m.username != null ? '@${m.username}' : m.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: m.role == 'admin' ? Text(context.tr('admin'), style: TextStyle(color: cs.primary, fontSize: 13)) : null,
                  onTap: m.id == app.myId
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen.user(profile: m))),
                ),
          ]),

          // ── Shared media and files ──
          if (chat != null) ...[
            const SizedBox(height: 14),
            _Section(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 0, icon: const Icon(Icons.photo_library_rounded), label: Text(context.tr('media'))),
                    ButtonSegment(value: 1, icon: const Icon(Icons.insert_drive_file_rounded), label: Text(context.tr('files'))),
                  ],
                  selected: {_tab},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _tab = v.first),
                ),
              ),
              _SharedItems(chat: chat, images: _tab == 0),
            ]),
          ],
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.danger = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = danger ? Brand.pomegranate : cs.primary;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(children: [
                Icon(icon, color: color),
                const SizedBox(height: 4),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.value, required this.label, this.ltr = false, this.onTap});
  final IconData icon;
  final String value, label;
  final bool ltr;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Directionality(
          textDirection: ltr ? TextDirection.ltr : Directionality.of(context),
          child: Text(value, textAlign: ltr && Directionality.of(context) == TextDirection.rtl ? TextAlign.right : null),
        ),
        subtitle: Text(label),
        onTap: onTap ??
            () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
            },
      );
}

class _SharedItems extends StatefulWidget {
  const _SharedItems({required this.chat, required this.images});
  final Chat chat;
  final bool images;

  @override
  State<_SharedItems> createState() => _SharedItemsState();
}

class _SharedItemsState extends State<_SharedItems> {
  @override
  void initState() {
    super.initState();
    final app = AppScope.read(context);
    if (app.messagesOf(widget.chat.id) == null) app.loadMessages(widget.chat.id);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final msgs = (app.messagesOf(widget.chat.id) ?? const <Message>[])
        .where((m) => !m.deleted && m.filePath != null && (widget.images ? m.kind == MsgKind.image : m.kind != MsgKind.image))
        .toList()
        .reversed
        .toList();
    if (msgs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Text(context.tr('no_media'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    if (widget.images) {
      return GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(4),
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        children: [
          for (var k = 0; k < msgs.length; k++)
            GestureDetector(
              onTap: () => GalleryViewer.open(context, [for (final x in msgs) (path: x.filePath, bytes: null)], k),
              child: Hero(tag: photoHeroTag((path: msgs[k].filePath, bytes: null)), child: AttachmentImage(path: msgs[k].filePath)),
            ),
        ],
      );
    }
    return Column(children: [
      for (final m in msgs)
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(m.kind == MsgKind.voice ? Icons.mic_rounded : Icons.insert_drive_file_rounded, color: Colors.white),
          ),
          title: Text(m.kind == MsgKind.voice ? context.tr('voice_message') : (m.fileName ?? ''), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(localDigits(formatBytes(m.fileSize), context.lang)),
          onTap: () async {
            final url = await app.fileUrl(m.filePath!);
            if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
          },
        ),
    ]);
  }
}
