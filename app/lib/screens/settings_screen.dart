import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../config.dart';
import '../l10n/strings.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final me = app.me;
    final cs = Theme.of(context).colorScheme;

    String themeLabel(ThemeMode m) => switch (m) {
          ThemeMode.system => context.tr('theme_system'),
          ThemeMode.light => context.tr('theme_light'),
          ThemeMode.dark => context.tr('theme_dark'),
        };

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Avatar(seed: app.myId ?? '', label: me?.name ?? app.myEmail, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me?.name ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(app.myEmail, style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: context.tr('edit_name'),
                  onPressed: () => _edit(context, 'edit_name', me?.displayName ?? '', (v) => app.updateProfile(displayName: v)),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              _Tile(
                icon: Icons.alternate_email_rounded,
                color: Brand.accentDeep,
                title: context.tr('username'),
                value: me?.username != null ? '@${me!.username}' : context.tr('not_set'),
                onTap: () => _edit(context, 'username', me?.username ?? '', (v) => app.updateProfile(username: v),
                    hint: context.tr('username_hint'), ltr: true, errorKey: 'username_taken'),
              ),
              _Tile(
                icon: Icons.translate_rounded,
                color: cs.primary,
                title: context.tr('language'),
                value: app.lang.label,
                onTap: () => _pick<AppLang>(context, context.tr('language'), AppLang.values, app.lang, (l) => l.label, app.setLang),
              ),
              _Tile(
                icon: Icons.dark_mode_outlined,
                color: const Color(0xFF6A3FA0),
                title: context.tr('theme'),
                value: themeLabel(app.themeMode),
                onTap: () => _pick<ThemeMode>(context, context.tr('theme'), ThemeMode.values, app.themeMode, themeLabel, app.setTheme),
              ),
              _Tile(
                icon: Icons.shield_outlined,
                color: const Color(0xFF1E8C6E),
                title: context.tr('privacy'),
                onTap: () => _info(context, context.tr('privacy'), context.tr('privacy_body')),
              ),
              _Tile(
                icon: Icons.dns_outlined,
                color: const Color(0xFF0F7FA8),
                title: context.tr('server'),
                value: Uri.parse(AppConfig.supabaseUrl).host,
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              _Tile(
                icon: Icons.info_outline_rounded,
                color: cs.primary,
                title: context.tr('about'),
                value: '${context.digits(Brand.version)} · ${context.tr('prototype')}',
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
                        TextButton(
                            onPressed: () => Navigator.pop(d, true),
                            child: Text(d.tr('logout'), style: const TextStyle(color: Brand.pomegranate))),
                      ],
                    ),
                  );
                  if (ok == true) await app.signOut();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Column(
            children: [
              const PaighamLogo(size: 40, background: false),
              const SizedBox(height: 6),
              Text('${context.tr('app_name')} ${context.digits(Brand.version)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
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
          for (final x in values)
            ListTile(
              leading: Icon(x == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: x == current ? Theme.of(ctx).colorScheme.primary : null),
              title: Text(label(x)),
              onTap: () => Navigator.pop(ctx, x),
            ),
        ],
      ),
    );
    if (v != null) onPick(v);
  }

  Future<void> _edit(BuildContext context, String titleKey, String initial, Future<bool> Function(String) save,
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
    final ok = await save(v);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(errorKey))));
    }
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
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: danger ? Brand.pomegranate : null)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(value!, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5)),
            ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}
