import 'notify_screen.dart';

import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../config.dart';
import '../l10n/strings.dart';
import '../services/e2e.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';
import 'chats_screen.dart';
import 'profile_screen.dart';
import 'storage_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _changePhoto(BuildContext context, AppController app) async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return;
    final f = files.first;
    final size = await f.length();
    if (!context.mounted) return;
    if (size != null && size > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('photo_too_big'))));
      return;
    }
    await app.uploadAvatar(f.name, await f.readAsBytes());
  }

  void _showQr(BuildContext context, AppController app) {
    final me = app.me;
    final handle = me?.username != null ? '@${me!.username}' : app.myEmail;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ctx.tr('my_qr'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(
                  data: 'paigham:$handle',
                  size: 200,
                  eyeStyle: const QrEyeStyle(color: Brand.blueDeep, eyeShape: QrEyeShape.circle),
                ),
              ),
              const SizedBox(height: 12),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(handle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final me = app.me;
    final cs = Theme.of(context).colorScheme;
    final pad = MediaQuery.paddingOf(context);
    final archived = app.chats.where((c) => c.archived).length;
    final handle = [app.myEmail, if (me?.username != null) '@${me!.username}'].join(' • ');

    String themeLabel(ThemeMode m) => switch (m) {
      ThemeMode.system => context.tr('theme_system'),
      ThemeMode.light => context.tr('theme_light'),
      ThemeMode.dark => context.tr('theme_dark'),
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(12, pad.top + 6, 12, 120),
      children: [
        // round buttons, like Telegram
        Row(
          children: [
            _RoundIcon(icon: Icons.qr_code_2_rounded, tooltip: context.tr('my_qr'), onTap: () => _showQr(context, app)),
            const Spacer(),
            _RoundIcon(
              icon: Icons.edit_rounded,
              tooltip: context.tr('edit_name'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen.me())),
            ),
          ],
        ),
        // photo, name, handle
        Center(
          child: GestureDetector(
            onTap: () => _changePhoto(context, app),
            child: Stack(
              children: [
                Avatar(seed: app.myId ?? '', label: me?.name ?? app.myEmail, imageUrl: me?.avatarUrl, size: 100),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                    ),
                    child: const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          me?.name ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            handle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 18),
        // Telegram: Saved Messages at the top of Settings
        _Group(
          children: [
            _Tile(
              icon: Icons.bookmark_rounded,
              color: const Color(0xFF3390EC),
              title: context.tr('saved_messages'),
              subtitle: context.tr('saved_sub'),
              onTap: () => openSavedMessages(context),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Group(
          children: [
            _Tile(
              icon: CupertinoIcons.person_crop_circle_fill,
              color: const Color(0xFF3390EC),
              title: context.tr('account'),
              subtitle: context.tr('account_sub'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen.me())),
            ),
            _Tile(
              icon: Icons.chat_rounded,
              color: const Color(0xFFF5A623),
              title: context.tr('chat_settings'),
              subtitle: context.tr('chat_settings_sub'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ChatSettingsPage())),
            ),
            _Tile(
              icon: Icons.key_rounded,
              color: const Color(0xFF31B545),
              title: context.tr('privacy'),
              subtitle: context.tr('privacy_sub'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _PrivacyPage())),
            ),
            _Tile(
              icon: Icons.pie_chart_rounded,
              color: const Color(0xFF3390EC),
              title: context.tr('data_storage'),
              subtitle: context.tr('data_storage_sub'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorageScreen())),
            ),
            _Tile(
              icon: Icons.notifications_rounded,
              color: const Color(0xFFF0544C),
              title: context.tr('notifications'),
              subtitle: context.tr('notifications_sub'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotifyScreen(page: true))),
            ),
            _Tile(
              icon: Icons.translate_rounded,
              color: const Color(0xFF8E6CEF),
              title: context.tr('language'),
              subtitle: app.lang.label,
              onTap: () => _pick<AppLang>(context, context.tr('language'), AppLang.values, app.lang, (l) => l.label, app.setLang),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Group(
          children: [
            _Tile(
              icon: Icons.bookmark_rounded,
              color: const Color(0xFF3390EC),
              title: context.tr('saved_messages'),
              subtitle: context.tr('saved_sub'),
              onTap: () => openSavedMessages(context),
            ),
            if (archived > 0)
              _Tile(
                icon: Icons.archive_rounded,
                color: const Color(0xFF8A98A8),
                title: context.tr('archived_chats'),
                subtitle: context.digits(archived),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ArchivedChatsScreen(
                      onOpen: (c) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id))),
                    ),
                  ),
                ),
              ),
            _Tile(
              icon: Icons.palette_rounded,
              color: const Color(0xFF2AA3C8),
              title: context.tr('theme'),
              subtitle: themeLabel(app.themeMode),
              onTap: () => _pick<ThemeMode>(context, context.tr('theme'), ThemeMode.values, app.themeMode, themeLabel, app.setTheme),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Group(
          children: [
            _Tile(
              icon: Icons.dns_rounded,
              color: const Color(0xFF5E6E7E),
              title: context.tr('server'),
              subtitle: Uri.tryParse(AppConfig.supabaseUrl)?.host ?? '',
              onTap: () {},
            ),
            _Tile(icon: Icons.info_rounded, color: const Color(0xFF3390EC), title: context.tr('about'), subtitle: context.digits(Brand.version), onTap: () {}),
            _Tile(
              icon: Icons.logout_rounded,
              color: Brand.pomegranate,
              title: context.tr('logout'),
              danger: true,
              onTap: () async {
                final ok = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (d) => CupertinoAlertDialog(
                    content: Text(d.tr('logout_q')),
                    actions: [
                      CupertinoDialogAction(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
                      CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(d, true), child: Text(d.tr('logout'))),
                    ],
                  ),
                );
                if (ok == true) await app.signOut();
              },
            ),
          ],
        ),
        const SizedBox(height: 22),
        Center(
          child: Column(
            children: [
              const PaighamLogo(size: 40),
              const SizedBox(height: 8),
              Text(
                '${context.tr('app_name')} ${context.digits(Brand.version)}',
                style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
              ),
              Text(context.tr('made_for'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick<T>(BuildContext context, String title, List<T> values, T current, String Function(T) label, void Function(T) onPick) async {
    final v = await showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            child: Column(
              children: [for (final x in values) RadioListTile<T>(value: x, title: Text(label(x)))],
            ),
          ),
        ],
      ),
    );
    if (v != null) onPick(v);
  }
}

/// Night mode, theme and glass in one page.
class _ChatSettingsPage extends StatelessWidget {
  const _ChatSettingsPage();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final dark = app.themeMode == ThemeMode.dark || (app.themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('chat_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Group(
            children: [
              SwitchListTile.adaptive(
                secondary: const _Ico(Icons.dark_mode_rounded, Color(0xFF5B6BF5)),
                title: Text(context.tr('night_mode'), style: const TextStyle(fontWeight: FontWeight.w600)),
                value: dark,
                onChanged: (v) => app.setTheme(v ? ThemeMode.dark : ThemeMode.light),
              ),
              SwitchListTile.adaptive(
                secondary: const _Ico(Icons.blur_on_rounded, Color(0xFF2AA3C8)),
                title: Text(context.tr('glass_effect'), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(context.tr('glass_effect_sub')),
                value: app.glass,
                onChanged: app.setGlass,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dark ? const Color(0xFF202B38) : Colors.white,
        elevation: dark ? 0 : 1,
        shadowColor: Colors.black12,
        shape: CircleBorder(side: BorderSide(color: dark ? const Color(0x14FFFFFF) : const Color(0x0A000000))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 46, height: 46, child: Icon(icon, color: Theme.of(context).colorScheme.onSurface)),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1C2733) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: dark ? const Color(0x10FFFFFF) : const Color(0x08000000)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );
  }
}

class _Ico extends StatelessWidget {
  const _Ico(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(9)),
    child: Icon(icon, color: Colors.white, size: 20),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.title, this.subtitle, required this.onTap, this.danger = false});
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 11, 14, 11),
        child: Row(
          children: [
            _Ico(icon, color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: danger ? Brand.pomegranate : null),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Privacy: what end-to-end encryption protects, and the message PIN.
class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  Future<void> _changePin(BuildContext context) async {
    final app = AppScope.read(context);
    final a = TextEditingController(), b = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final pin = await showDialog<String>(
      context: context,
      builder: (d) {
        String? err;
        return StatefulBuilder(
          builder: (d, set) => AlertDialog(
            title: Text(d.tr('change_pin')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: a,
                  obscureText: true,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(hintText: d.tr('pin_hint')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: b,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(hintText: d.tr('pin_again')),
                ),
                if (err != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(d.tr(err!), style: const TextStyle(color: Brand.pomegranate)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: Text(d.tr('cancel'))),
              TextButton(
                onPressed: () {
                  final weak = E2E.pinProblem(a.text);
                  if (weak != null) return set(() => err = weak);
                  if (a.text != b.text) return set(() => err = 'pin_mismatch');
                  Navigator.pop(d, a.text);
                },
                child: Text(d.tr('save')),
              ),
            ],
          ),
        );
      },
    );
    if (pin == null) return;
    final err = await app.changePin(pin);
    messenger.showSnackBar(SnackBar(content: Text(app.s.get(err ?? 'pin_changed'))));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('privacy'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
            child: Column(
              children: [
                Icon(Icons.lock_rounded, size: 44, color: cs.primary),
                const SizedBox(height: 10),
                Text(context.tr('e2e_title'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  context.tr('e2e_create_body'),
                  textAlign: TextAlign.center,
                  style: TextStyle(height: 1.6, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.password_rounded),
              title: Text(context.tr('change_pin')),
              subtitle: Text(context.tr('pin_tip')),
              onTap: () => _changePin(context),
            ),
          ),
        ],
      ),
    );
  }
}
