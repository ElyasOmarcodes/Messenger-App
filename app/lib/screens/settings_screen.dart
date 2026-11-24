import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../config.dart';
import '../l10n/strings.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final me = app.me;
    final cs = Theme.of(context).colorScheme;
    final dark = app.themeMode == ThemeMode.dark ||
        (app.themeMode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    String themeLabel(ThemeMode m) => switch (m) {
          ThemeMode.system => context.tr('theme_system'),
          ThemeMode.light => context.tr('theme_light'),
          ThemeMode.dark => context.tr('theme_dark'),
        };

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 120),
      children: [
        _Group(children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Avatar(seed: app.myId ?? '', label: me?.name ?? app.myEmail, imageUrl: me?.avatarUrl, size: 56),
            title: Text(me?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            subtitle: Directionality(textDirection: TextDirection.ltr, child: Text(app.myEmail, textAlign: TextAlign.start)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen.me())),
          ),
        ]),
        _Header(context.tr('appearance_sub')),
        _Group(children: [
          SwitchListTile(
            secondary: const _Ico(Icons.dark_mode_rounded, Color(0xFF5B6BF5)),
            title: Text(context.tr('night_mode'), style: const TextStyle(fontWeight: FontWeight.w600)),
            value: dark,
            onChanged: (v) => app.setTheme(v ? ThemeMode.dark : ThemeMode.light),
          ),
          _Tile(
            icon: Icons.brightness_auto_rounded,
            color: const Color(0xFF8E6CEF),
            title: context.tr('theme'),
            value: themeLabel(app.themeMode),
            onTap: () => _pick<ThemeMode>(context, context.tr('theme'), ThemeMode.values, app.themeMode, themeLabel, app.setTheme),
          ),
          _Tile(
            icon: Icons.translate_rounded,
            color: const Color(0xFF3390EC),
            title: context.tr('language'),
            value: app.lang.label,
            onTap: () => _pick<AppLang>(context, context.tr('language'), AppLang.values, app.lang, (l) => l.label, app.setLang),
          ),
        ]),
        _Header(context.tr('account')),
        _Group(children: [
          _Tile(
            icon: Icons.notifications_rounded,
            color: const Color(0xFFF0544C),
            title: context.tr('notifications'),
            onTap: () => _info(context, context.tr('notifications'), context.tr('notifications_body')),
          ),
          _Tile(
            icon: Icons.lock_rounded,
            color: const Color(0xFF31B545),
            title: context.tr('privacy'),
            onTap: () => _info(context, context.tr('privacy'), context.tr('privacy_body')),
          ),
          _Tile(
            icon: Icons.dns_rounded,
            color: const Color(0xFF2AA3C8),
            title: context.tr('server'),
            value: Uri.tryParse(AppConfig.supabaseUrl)?.host.split('.').first ?? '',
            onTap: () {},
          ),
        ]),
        _Header(context.tr('about')),
        _Group(children: [
          _Tile(
            icon: Icons.info_rounded,
            color: const Color(0xFF3390EC),
            title: context.tr('about'),
            value: context.digits(Brand.version),
            onTap: () {},
          ),
          _Tile(
            icon: Icons.logout_rounded,
            color: Brand.pomegranate,
            title: context.tr('logout'),
            danger: true,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  content: Text(d.tr('logout_q')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
                    TextButton(onPressed: () => Navigator.pop(d, true), child: Text(d.tr('logout'), style: const TextStyle(color: Brand.pomegranate))),
                  ],
                ),
              );
              if (ok == true) await app.signOut();
            },
          ),
        ]),
        const SizedBox(height: 22),
        Center(
          child: Column(children: [
            const PaighamLogo(size: 44),
            const SizedBox(height: 8),
            Text('${context.tr('app_name')} ${context.digits(Brand.version)}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
            Text(context.tr('made_for'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
          ]),
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
            child: Column(children: [
              for (final x in values) RadioListTile<T>(value: x, title: Text(label(x))),
            ]),
          ),
        ],
      ),
    );
    if (v != null) onPick(v);
  }

  void _info(BuildContext context, String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body, style: const TextStyle(height: 1.6)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(18, 18, 18, 8),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 14)),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _Ico extends StatelessWidget {
  const _Ico(this.icon, this.color);
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Colors.white, size: 20),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.color, required this.title, this.value, required this.onTap, this.danger = false});
  final IconData icon;
  final Color color;
  final String title;
  final String? value;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: _Ico(icon, color),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? Brand.pomegranate : null)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(value!, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}
