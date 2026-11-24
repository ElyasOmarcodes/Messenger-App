import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/strings.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import 'new_chat_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final p = app.profile!;
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
            child: Column(
              children: [
                Row(
                  children: [
                    Avatar(seed: p.id, label: p.name, size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          if (p.phone.isNotEmpty)
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(p.phone, style: TextStyle(color: cs.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('edit_name'),
                      onPressed: () => _editName(context, app),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                MyIdCard(id: p.id),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              _Tile(
                icon: Icons.translate_rounded,
                color: cs.primary,
                title: context.tr('language'),
                value: app.lang.label,
                onTap: () => _pick<AppLang>(
                  context,
                  context.tr('language'),
                  AppLang.values,
                  app.lang,
                  (l) => l.label,
                  app.setLang,
                ),
              ),
              _Tile(
                icon: Icons.dark_mode_outlined,
                color: const Color(0xFF6A3FA0),
                title: context.tr('theme'),
                value: themeLabel(app.themeMode),
                onTap: () => _pick<ThemeMode>(
                  context,
                  context.tr('theme'),
                  ThemeMode.values,
                  app.themeMode,
                  themeLabel,
                  app.setTheme,
                ),
              ),
              _Tile(
                icon: Icons.notifications_none_rounded,
                color: Brand.saffronDeep,
                title: context.tr('notifications'),
                value: context.tr('coming_soon'),
                onTap: () {},
              ),
              _Tile(
                icon: Icons.shield_outlined,
                color: const Color(0xFF1E8C6E),
                title: context.tr('privacy'),
                onTap: () => _info(context, context.tr('privacy'), context.tr('encryption_note')),
              ),
              _Tile(
                icon: Icons.dns_outlined,
                color: const Color(0xFF0F7FA8),
                title: context.tr('relay_server'),
                value: Uri.parse(app.relayUrl).host,
                onTap: () => _editRelay(context, app),
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
                onTap: () => _about(context),
              ),
              _Tile(
                icon: Icons.delete_forever_outlined,
                color: Brand.pomegranate,
                title: context.tr('reset_app'),
                danger: true,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      content: Text(d.tr('reset_q')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
                        TextButton(
                          onPressed: () => Navigator.pop(d, true),
                          child: Text(d.tr('delete'), style: const TextStyle(color: Brand.pomegranate)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await app.reset();
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
              Text('${context.tr('app_name')} ${context.digits(Brand.version)}', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700)),
              Text(context.tr('made_for'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pick<T>(
    BuildContext context,
    String title,
    List<T> values,
    T current,
    String Function(T) label,
    void Function(T) onPick,
  ) async {
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

  Future<void> _editName(BuildContext context, AppController app) async {
    final c = TextEditingController(text: app.profile!.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('edit_name')),
        content: TextField(controller: c, autofocus: true, maxLength: 40, decoration: const InputDecoration(counterText: '')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    if (v != null) app.updateName(v);
  }

  Future<void> _editRelay(BuildContext context, AppController app) async {
    final c = TextEditingController(text: app.relayUrl);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('relay_server')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ctx.tr('relay_hint'), style: const TextStyle(height: 1.5)),
            const SizedBox(height: 12),
            Directionality(textDirection: TextDirection.ltr, child: TextField(controller: c)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(ctx.tr('save'))),
        ],
      ),
    );
    if (v != null) app.setRelay(v);
  }

  void _info(BuildContext context, String title, String body) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body, style: const TextStyle(height: 1.6)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
        ),
      );

  void _about(BuildContext context) {
    const services = [
      ('ntfy.sh', 'real-time relay'),
      ('Open-Meteo', 'weather'),
      ('AlAdhan', 'prayer times'),
      ('ExchangeRate-API', 'currency rates'),
      ('AlQuran Cloud', 'Quran + Pashto/Dari translation'),
      ('Vazirmatn', 'font (OFL)'),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const PaighamLogo(size: 36),
            const SizedBox(width: 10),
            Text(ctx.tr('app_name')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${ctx.tr('version')}: ${Brand.version} (${ctx.tr('prototype')})'),
            const SizedBox(height: 12),
            Text(ctx.tr('free_services'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            for (final (name, what) in services)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('• $name — $what', style: const TextStyle(fontSize: 13.5)),
                ),
              ),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ok')))],
      ),
    );
  }
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
          if (value != null) Text(value!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}
