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
  const ProfileScreen.me({super.key}) : _kind = _Kind.me, profile = null, chatId = null;
  const ProfileScreen.user({super.key, required this.profile, this.chatId}) : _kind = _Kind.user;
  const ProfileScreen.group({super.key, required this.chatId}) : _kind = _Kind.group, profile = null;

  final _Kind _kind;
  final Profile? profile;
  final String? chatId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _tab = 0; // 0 media, 1 files, 2 voice, 3 links
  bool _expanded = false; // big photo (tap or pull down on the avatar)

  void _setExpanded(bool v) {
    if (v == _expanded) return;
    HapticFeedback.selectionClick();
    setState(() => _expanded = v);
  }

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

  Future<void> _edit(
    String titleKey,
    String initial,
    Future<bool> Function(String) save, {
    String? hint,
    bool ltr = false,
    String errorKey = 'err_generic',
  }) async {
    final c = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr(titleKey)),
        content: Directionality(
          textDirection: ltr ? TextDirection.ltr : Directionality.of(ctx),
          child: TextField(
            controller: c,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(helperText: hint, helperMaxLines: 2),
          ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);

    late final String title, subtitle, seed;
    String? photo;
    bool group = false;
    final chat = widget.chatId == null ? null : app.chatById(widget.chatId!);
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
    final big = _expanded && photo != null;

    // ── action cards ──
    final actions = <Widget>[];
    if (widget._kind == _Kind.user) {
      actions.addAll([
        _Action(
          icon: Icons.chat_bubble_rounded,
          label: context.tr('message'),
          onBig: big,
          onTap: () async {
            final c = await _directChat(app, widget.profile!);
            if (c == null || !context.mounted) return;
            if (widget.chatId != null) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
            }
          },
        ),
        if (chat != null)
          _Action(
            icon: chat.muted ? Icons.notifications_off_rounded : Icons.notifications_rounded,
            label: context.tr(chat.muted ? 'unmute_chat' : 'mute_chat'),
            onBig: big,
            onTap: () => app.toggleMute(chat),
          ),
        _Action(
          icon: Icons.call_rounded,
          label: context.tr('voice_call'),
          onBig: big,
          onTap: () async {
            final c = await _directChat(app, widget.profile!);
            if (c != null && context.mounted) CallScope.read(context).call(c, withVideo: false);
          },
        ),
        _Action(
          icon: Icons.videocam_rounded,
          label: context.tr('video_call'),
          onBig: big,
          onTap: () async {
            final c = await _directChat(app, widget.profile!);
            if (c != null && context.mounted) CallScope.read(context).call(c, withVideo: true);
          },
        ),
      ]);
    } else if (widget._kind == _Kind.me) {
      actions.addAll([
        _Action(icon: Icons.add_a_photo_rounded, label: context.tr('change_photo'), onBig: big, onTap: () => _changePhoto(app)),
        _Action(
          icon: Icons.edit_rounded,
          label: context.tr('edit_name'),
          onBig: big,
          onTap: () => _edit('edit_name', app.me?.displayName ?? '', (v) => app.updateProfile(displayName: v)),
        ),
        _Action(icon: Icons.bookmark_rounded, label: context.tr('saved_short'), onBig: big, onTap: () => openSavedMessages(context)),
      ]);
    } else if (chat != null) {
      actions.addAll([
        _Action(
          icon: Icons.person_add_alt_1_rounded,
          label: context.tr('add_member'),
          onBig: big,
          onTap: () async {
            final p = await showDialog<Profile>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(ctx.tr('add_member')),
                content: SizedBox(
                  width: 420,
                  child: PersonFinder(buttonKey: 'add', onFound: (p) => Navigator.pop(ctx, p)),
                ),
              ),
            );
            if (p != null) await app.addMember(chat, p);
          },
        ),
        _Action(
          icon: chat.muted ? Icons.notifications_off_rounded : Icons.notifications_rounded,
          label: context.tr(chat.muted ? 'unmute_chat' : 'mute_chat'),
          onBig: big,
          onTap: () => app.toggleMute(chat),
        ),
        _Action(
          icon: Icons.logout_rounded,
          label: context.tr('leave'),
          danger: true,
          onBig: big,
          onTap: () async {
            await app.leaveChat(chat);
            if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
          },
        ),
      ]);
    }

    // ── header: avatar in a circle, or the photo across the whole width ──
    const avatar = 112.0;
    final smallH = pad.top + 16 + avatar + 14 + 34 + 24 + 18 + 74 + 12;
    final bigH = (size.width * 1.1).clamp(smallH + 60, size.height * 0.8);
    final headerH = big ? bigH : smallH;
    const dur = Duration(milliseconds: 340);
    const curve = Curves.easeOutCubic;
    final canPop = Navigator.of(context).canPop();
    final header = AnimatedContainer(
      duration: dur,
      curve: curve,
      height: headerH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // photo: grows from the circle to the full width
          AnimatedPositioned(
            duration: dur,
            curve: curve,
            top: big ? 0 : pad.top + 16,
            left: big ? 0 : (size.width - avatar) / 2,
            width: big ? size.width : avatar,
            height: big ? headerH : avatar,
            child: GestureDetector(
              onTap: () {
                if (photo != null) {
                  _setExpanded(!_expanded);
                } else if (widget._kind != _Kind.user) {
                  _changePhoto(app);
                }
              },
              child: AnimatedContainer(
                duration: dur,
                curve: curve,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(big ? 0 : avatar / 2)),
                child: photo == null
                    ? Avatar(seed: seed, label: title, group: group, size: avatar)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            photo,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            cacheWidth: (size.width * MediaQuery.devicePixelRatioOf(context)).round(),
                            errorBuilder: (_, _, _) => Avatar(seed: seed, label: title, group: group, size: avatar),
                          ),
                          // dark fade at the bottom so the name stays readable
                          AnimatedOpacity(
                            duration: dur,
                            opacity: big ? 1 : 0,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x33000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
                                  stops: [0, 0.25, 0.5, 1],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          // camera badge for my own photo / group photo
          if (widget._kind != _Kind.user && !big)
            Positioned(
              top: pad.top + 16 + avatar - 34,
              left: (size.width + avatar) / 2 - 34,
              child: GestureDetector(
                onTap: () => _changePhoto(app),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, size: 18, color: Colors.white),
                ),
              ),
            ),
          // name + status: under the circle, or at the photo's bottom corner
          AnimatedPositioned(
            duration: dur,
            curve: curve,
            left: 20,
            right: 20,
            top: big ? headerH - 74 - 20 - 64 : pad.top + 16 + avatar + 14,
            child: AnimatedAlign(
              duration: dur,
              curve: curve,
              alignment: big ? AlignmentDirectional.centerStart : Alignment.center,
              child: Column(
                crossAxisAlignment: big ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: big ? Colors.white : cs.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: big ? Colors.white70 : cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // action cards at the bottom of the header
          Positioned(left: 12, right: 12, bottom: 12, height: 74, child: Row(children: actions)),
          // round buttons
          if (canPop)
            PositionedDirectional(
              top: pad.top + 8,
              start: 10,
              child: _RoundButton(icon: Icons.arrow_back_rounded, onBig: big, tooltip: context.tr('back'), onTap: () => Navigator.of(context).maybePop()),
            ),
          if (big)
            PositionedDirectional(
              top: pad.top + 8,
              end: 10,
              child: _RoundButton(icon: Icons.close_fullscreen_rounded, onBig: big, tooltip: context.tr('close'), onTap: () => _setExpanded(false)),
            ),
        ],
      ),
    );

    // ── shared media / files ──
    final shared = chat == null ? null : _sharedOf(app, chat);
    return Scaffold(
      body: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          // pull down past the top to open the big photo, scroll up to close it
          if (photo != null && n.metrics.axis == Axis.vertical) {
            if (n.metrics.pixels < -60) _setExpanded(true);
            if (n.metrics.pixels > 40 && _expanded) _setExpanded(false);
          }
          return false;
        },
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: header),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: _Section(
                children: [
                  if (widget._kind == _Kind.me) ...[
                    _Info(icon: Icons.alternate_email_rounded, value: app.myEmail, label: context.tr('email'), ltr: true),
                    _Info(
                      icon: Icons.tag_rounded,
                      value: app.me?.username != null ? '@${app.me!.username}' : context.tr('not_set'),
                      label: context.tr('username'),
                      ltr: app.me?.username != null,
                      onTap: () => _edit(
                        'username',
                        app.me?.username ?? '',
                        (v) => app.updateProfile(username: v),
                        hint: context.tr('username_hint'),
                        ltr: true,
                        errorKey: 'username_taken',
                      ),
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
                        onTap: m.id == app.myId ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen.user(profile: m))),
                      ),
                ],
              ),
            ),
            if (shared != null) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
              SliverToBoxAdapter(child: _tabs(context, dark)),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              ..._sharedSlivers(context, app, shared),
            ],
            SliverToBoxAdapter(child: SizedBox(height: widget._kind == _Kind.me ? 120 : 30)),
          ],
        ),
      ),
    );
  }

  /// Telegram-style tab capsule: Media · Files · Voice · Links.
  Widget _tabs(BuildContext context, bool dark) {
    final cs = Theme.of(context).colorScheme;
    const keys = ['media', 'files', 'voice_message', 'links'];
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF202B38) : const Color(0xFFEEF1F5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dark ? const Color(0x14FFFFFF) : const Color(0x0A000000)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < keys.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == i ? (dark ? const Color(0xFF26405C) : Brand.blueMist) : Colors.transparent,
                    borderRadius: BorderRadius.circular(19),
                  ),
                  child: Text(
                    context.tr(keys[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w600,
                      color: _tab == i ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ({List<({String? path, Uint8List? bytes})> photos, List<Message> files, List<Message> voices, List<Message> links}) _sharedOf(AppController app, Chat chat) {
    final msgs = (app.messagesOf(chat.id) ?? const <Message>[]).where((m) => !m.deleted).toList().reversed;
    final photos = <({String? path, Uint8List? bytes})>[];
    final files = <Message>[], voices = <Message>[], links = <Message>[];
    final url = RegExp(r'https?://\S+');
    for (final m in msgs) {
      switch (m.kind) {
        case MsgKind.image:
          if (m.filePath != null) photos.add((path: m.filePath, bytes: null));
        case MsgKind.album:
          for (final it in m.albumItems) {
            final p = it['path'] as String?;
            if (p != null) photos.add((path: p, bytes: null));
          }
        case MsgKind.file:
          files.add(m);
        case MsgKind.voice:
          voices.add(m);
        default:
          if (url.hasMatch(m.body)) links.add(m);
      }
    }
    return (photos: photos, files: files, voices: voices, links: links);
  }

  List<Widget> _sharedSlivers(
    BuildContext context,
    AppController app,
    ({List<({String? path, Uint8List? bytes})> photos, List<Message> files, List<Message> voices, List<Message> links}) s,
  ) {
    final cs = Theme.of(context).colorScheme;
    Widget empty() => SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Text(
          context.tr('no_media'),
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ),
    );
    if (_tab == 0) {
      if (s.photos.isEmpty) return [empty()];
      // lazy grid: only the visible thumbnails are built and decoded
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 2, crossAxisSpacing: 2),
            itemCount: s.photos.length,
            itemBuilder: (_, k) => GestureDetector(
              onTap: () => GalleryViewer.open(context, s.photos, k),
              child: Hero(
                tag: photoHeroTag(s.photos[k]),
                child: AttachmentImage(path: s.photos[k].path),
              ),
            ),
          ),
        ),
      ];
    }
    final list = _tab == 1 ? s.files : (_tab == 2 ? s.voices : s.links);
    if (list.isEmpty) return [empty()];
    return [
      SliverList.builder(
        itemCount: list.length,
        itemBuilder: (_, i) {
          final m = list[i];
          final isLink = _tab == 3;
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: cs.primary,
              child: Icon(isLink ? Icons.link_rounded : (m.kind == MsgKind.voice ? Icons.mic_rounded : Icons.insert_drive_file_rounded), color: Colors.white),
            ),
            title: Text(
              isLink ? m.body : (m.kind == MsgKind.voice ? context.tr('voice_message') : (m.fileName ?? '')),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(isLink ? '' : localDigits(formatBytes(m.fileSize), context.lang)),
            onTap: () async {
              if (isLink) {
                final u = RegExp(r'https?://\S+').firstMatch(m.body)?.group(0);
                if (u != null) await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
                return;
              }
              final url = await app.fileUrl(m.filePath!);
              if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
          );
        },
      ),
    ];
  }
}

/// Round glass button (back, close) like Telegram's profile page.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.onBig, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final bool onBig;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: onBig ? Colors.black.withValues(alpha: 0.30) : (dark ? const Color(0xCC202B38) : const Color(0xCCEEF1F5)),
        shape: CircleBorder(
          side: BorderSide(color: Colors.white.withValues(alpha: onBig ? 0.25 : (dark ? 0.08 : 0.6)), width: 0.8),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: onBig ? Colors.white : Theme.of(context).colorScheme.onSurface)),
        ),
      ),
    );
  }
}

/// Rounded action card (message, mute, call, video…).
class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.danger = false, this.onBig = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool onBig;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = danger ? Brand.pomegranate : (onBig ? Colors.white : (dark ? Colors.white : Theme.of(context).colorScheme.primary));
    final bg = onBig ? Colors.black.withValues(alpha: 0.32) : (dark ? const Color(0xFF202B38) : const Color(0xFFEEF1F5));
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: onBig ? 0.18 : (dark ? 0.06 : 0.7)), width: 0.8),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg, size: 25),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
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
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C2733) : const Color(0xFFF3F5F8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dark ? const Color(0x10FFFFFF) : const Color(0x08000000)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
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
    onTap:
        onTap ??
        () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('copied'))));
        },
  );
}
