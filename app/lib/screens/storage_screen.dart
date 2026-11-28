import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/media_cache.dart';
import '../services/messenger.dart';
import '../widgets/chat_options.dart';

/// "Data and storage", like Telegram: how much the cache uses (per chat),
/// how long unopened media is kept, a size limit, auto-download, clear.
/// Everything stays on the server, so clearing only frees space on the phone.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  Map<String, int>? _sizes;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final s = await MediaCache.instance.store.sizes();
    if (mounted) setState(() => _sizes = s);
  }

  String _fmt(int b) => localDigits(formatBytes(b), context.lang);

  Future<void> _clear({String? folder}) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        content: Text(d.tr('clear_cache_q')),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(d, true), child: Text(d.tr('clear'))),
        ],
      ),
    );
    if (ok != true) return;
    await MediaCache.instance.store.clear(folder: folder);
    PaintingBinding.instance.imageCache.clear();
    await _measure();
  }

  Future<void> _pick(String title, List<(int, String)> options, int current, void Function(int) set) async {
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<int>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(ctx, v),
            child: Column(
              children: [for (final (v, l) in options) RadioListTile<int>(value: v, title: Text(l))],
            ),
          ),
        ],
      ),
    );
    if (v != null) {
      set(v);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _measure();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final card = dark ? const Color(0xFF1C2733) : Colors.white;
    final sizes = _sizes;
    final total = sizes?.values.fold<int>(0, (a, b) => a + b);
    final keep = <(int, String)>[(3, context.tr('keep_3d')), (7, context.tr('keep_1w')), (30, context.tr('keep_1m')), (0, context.tr('keep_forever'))];
    final limits = <(int, String)>[(1024, '1 GB'), (3072, '3 GB'), (5120, '5 GB'), (0, context.tr('no_limit'))];
    String label(List<(int, String)> l, int v) => l.firstWhere((e) => e.$1 == v, orElse: () => l.last).$2;
    final perChat = sizes == null ? const <MapEntry<String, int>>[] : (sizes.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));

    Widget group(List<Widget> children) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(22)),
      child: Material(
        type: MaterialType.transparency,
        child: Column(children: children),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('data_storage'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          group([
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
              child: Column(
                children: [
                  Icon(Icons.pie_chart_rounded, size: 54, color: cs.primary),
                  const SizedBox(height: 8),
                  Text(total == null ? '…' : _fmt(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  Text(context.tr('cache_used'), style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text(
                    context.tr(MediaCache.instance.persistent ? 'cache_note' : 'cache_note_web'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (total ?? 0) == 0 ? null : () => _clear(),
                    icon: const Icon(Icons.cleaning_services_rounded),
                    label: Text(context.tr('clear_cache')),
                  ),
                ],
              ),
            ),
          ]),
          group([
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text(context.tr('keep_media')),
              subtitle: Text(context.tr('keep_media_sub')),
              trailing: Text(
                label(keep, app.keepDays),
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
              ),
              onTap: () => _pick(context.tr('keep_media'), keep, app.keepDays, app.setKeepDays),
            ),
            ListTile(
              leading: const Icon(Icons.sd_storage_outlined),
              title: Text(context.tr('max_cache')),
              trailing: Text(
                label(limits, app.maxCacheMb),
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
              ),
              onTap: () => _pick(context.tr('max_cache'), limits, app.maxCacheMb, app.setMaxCache),
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.network_check_rounded),
              title: Text(context.tr('data_saver')),
              subtitle: Text(context.tr('data_saver_sub')),
              value: app.dataSaver,
              onChanged: app.setDataSaver,
            ),
            SwitchListTile.adaptive(
              secondary: const Icon(Icons.photo_outlined),
              title: Text(context.tr('auto_photos')),
              subtitle: Text(context.tr('auto_photos_sub')),
              value: app.autoPhotos,
              onChanged: app.setAutoPhotos,
            ),
          ]),
          if (perChat.isNotEmpty)
            group([
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.tr('by_chat'),
                    style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              for (final e in perChat)
                Builder(
                  builder: (context) {
                    final chat = app.chatById(e.key);
                    final isAvatars = e.key == 'avatars';
                    return ListTile(
                      leading: chat != null
                          ? ChatAvatar(chat: chat, size: 40)
                          : CircleAvatar(child: Icon(isAvatars ? CupertinoIcons.person_crop_circle_fill : Icons.folder_rounded)),
                      title: Text(
                        chat != null ? app.chatTitle(chat) : context.tr(isAvatars ? 'profile_photos' : (e.key == 'stories' ? 'stories_cache' : 'other_media')),
                      ),
                      subtitle: Text(_fmt(e.value)),
                      trailing: IconButton(
                        tooltip: context.tr('clear'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _clear(folder: e.key),
                      ),
                    );
                  },
                ),
            ]),
          if (sizes != null && perChat.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(context.tr('cache_empty'), style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ),
        ],
      ),
    );
  }
}
