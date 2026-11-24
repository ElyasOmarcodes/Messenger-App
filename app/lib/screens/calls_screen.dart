import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';

/// Calls are planned for phase two; this tab says so honestly and shows
/// what is coming.
class CallsScreen extends StatelessWidget {
  const CallsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      (Icons.call_rounded, 'rm_calls'),
      (Icons.videocam_rounded, 'rm_video'),
      (Icons.mic_rounded, 'rm_voice_notes'),
      (Icons.photo_library_rounded, 'rm_media'),
      (Icons.lock_rounded, 'rm_e2e'),
      (Icons.dns_rounded, 'rm_server'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Brand.lapisBright, Brand.lapisDeep],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _circle(Icons.call_rounded),
                  const SizedBox(width: 10),
                  _circle(Icons.videocam_rounded),
                ],
              ),
              const SizedBox(height: 16),
              Text(context.tr('calls_title'), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(context.tr('calls_body'), style: const TextStyle(color: Color(0xDDFFFFFF), height: 1.55)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Brand.saffron, borderRadius: BorderRadius.circular(20)),
                child: Text(context.tr('coming_soon'), style: const TextStyle(color: Brand.ink, fontWeight: FontWeight.w700, fontSize: 12.5)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(context.tr('roadmap'), style: TextStyle(fontWeight: FontWeight.w800, color: cs.onSurfaceVariant)),
        ),
        Card(
          child: Column(
            children: [
              for (final (icon, key) in items)
                ListTile(
                  leading: Icon(icon, color: cs.primary),
                  title: Text(context.tr(key)),
                  trailing: Icon(Icons.schedule_rounded, size: 18, color: cs.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circle(IconData icon) => Container(
        width: 46,
        height: 46,
        decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white),
      );
}
