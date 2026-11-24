import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../widgets/avatar.dart';
import 'call_screen.dart';

/// Call history with one-tap call back.
class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});

  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  Future<List<CallRecord>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= CallScope.read(context).history();
  }

  Future<void> _refresh() async {
    final f = CallScope.read(context).history();
    setState(() => _future = f);
    await f;
  }

  Future<void> _callBack(CallRecord r, bool video) async {
    final app = AppScope.read(context);
    final chat = app.chatById(r.chatId);
    if (chat == null) return;
    final err = await CallScope.read(context).call(chat, withVideo: video);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr(err))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = Strings(context.lang);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<CallRecord>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 90),
              Icon(Icons.call_rounded, size: 64, color: cs.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(context.tr('no_calls'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(context.tr('no_calls_sub'), textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ]);
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final r = list[i];
              final missed = !r.outgoing && (r.status == 'missed' || r.status == 'declined' && r.answeredAt == null);
              final d = r.duration;
              final when = '${chatListTime(r.createdAt, context.lang, s)} · ${hhmm(r.createdAt, context.lang)}';
              return ListTile(
                leading: Avatar(seed: r.peerId, label: r.peerName, imageUrl: r.peerAvatar == null ? null : '$avatarBaseUrl/${r.peerAvatar}', size: 48),
                title: Text(r.peerName, style: TextStyle(fontWeight: FontWeight.w700, color: missed ? Brand.pomegranate : null)),
                subtitle: Row(children: [
                  Icon(r.outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
                      size: 16, color: missed ? Brand.pomegranate : const Color(0xFF1E8C6E)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      d != null ? '$when · ${context.digits('${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}')}' : when,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                trailing: IconButton(
                  icon: Icon(r.video ? Icons.videocam_rounded : Icons.call_rounded, color: cs.primary),
                  onPressed: () => _callBack(r, r.video),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
