import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';

/// Fits a photo of w×h into the bubble: keeps its shape, never too thin or tall.
Size photoBox(double? w, double? h, {double maxW = 270, double maxH = 340, double minW = 150}) {
  if (w == null || h == null || w <= 0 || h <= 0) return Size(maxW, maxW * 0.75);
  final ratio = (w / h).clamp(0.5, 2.2);
  var bw = maxW, bh = bw / ratio;
  if (bh > maxH) {
    bh = maxH;
    bw = math.max(minW, bh * ratio);
  }
  return Size(bw, bh);
}

/// Loads a private attachment (or shows local bytes while uploading).
class AttachmentImage extends StatelessWidget {
  const AttachmentImage({super.key, this.path, this.bytes, this.fit = BoxFit.cover});
  final String? path;
  final Uint8List? bytes;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: Colors.black12);
    if (bytes != null) return Image.memory(bytes!, fit: fit, gaplessPlayback: true);
    if (path == null) return placeholder;
    return FutureBuilder<String?>(
      future: AppScope.read(context).fileUrl(path!),
      builder: (_, s) => s.data == null
          ? placeholder
          : Image.network(
              s.data!,
              fit: fit,
              gaplessPlayback: true,
              loadingBuilder: (c, child, p) => p == null ? child : placeholder,
              errorBuilder: (_, _, _) => Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined)),
            ),
    );
  }
}

/// Full-screen, swipeable photo viewer.
class GalleryViewer extends StatefulWidget {
  const GalleryViewer({super.key, required this.items, this.initial = 0});
  final List<({String? path, Uint8List? bytes})> items;
  final int initial;

  static void open(BuildContext context, List<({String? path, Uint8List? bytes})> items, int i) =>
      Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => GalleryViewer(items: items, initial: i),
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      ));

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late int _i = widget.initial;
  late final _ctl = PageController(initialPage: widget.initial);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(context.digits('${_i + 1} / ${widget.items.length}'), style: const TextStyle(color: Colors.white, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () async {
              final p = widget.items[_i].path;
              if (p == null) return;
              final url = await AppScope.read(context).fileUrl(p);
              if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _ctl,
        itemCount: widget.items.length,
        onPageChanged: (i) => setState(() => _i = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 5,
          child: Center(child: AttachmentImage(path: widget.items[i].path, bytes: widget.items[i].bytes, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

/// Telegram-style album grid (2–10 photos).
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.message, this.width = 270});
  final Message message;
  final double width;

  @override
  Widget build(BuildContext context) {
    final items = message.albumItems;
    final local = message.localAlbum;
    final n = local?.length ?? items.length;
    final all = [
      for (var i = 0; i < n; i++)
        (path: i < items.length ? items[i]['path'] as String? : null, bytes: local != null && i < local.length ? local[i] : null),
    ];
    Widget tile(int i, double w, double h) => GestureDetector(
          onTap: () => GalleryViewer.open(context, all, i),
          child: SizedBox(width: w, height: h, child: AttachmentImage(path: all[i].path, bytes: all[i].bytes)),
        );
    const g = 2.0;
    final rows = <Widget>[];
    if (n == 2) {
      rows.add(Row(children: [tile(0, (width - g) / 2, 170), const SizedBox(width: g), tile(1, (width - g) / 2, 170)]));
    } else if (n == 3) {
      final big = width * 0.62, side = width - big - g;
      rows.add(Row(children: [
        tile(0, big, 240),
        const SizedBox(width: g),
        Column(children: [tile(1, side, (240 - g) / 2), const SizedBox(height: g), tile(2, side, (240 - g) / 2)]),
      ]));
    } else {
      // first row: 2 tiles; remaining rows: up to 3 tiles each
      final half = (width - g) / 2;
      rows.add(Row(children: [tile(0, half, 150), const SizedBox(width: g), tile(1, half, 150)]));
      for (var i = 2; i < n; i += 3) {
        final count = math.min(3, n - i);
        final w = (width - g * (count - 1)) / count;
        rows.add(const SizedBox(height: g));
        rows.add(Row(children: [
          for (var k = 0; k < count; k++) ...[if (k > 0) const SizedBox(width: g), tile(i + k, w, 110)],
        ]));
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(children: [
        Column(mainAxisSize: MainAxisSize.min, children: rows),
        if (message.pending) const Positioned.fill(child: Center(child: CircularProgressIndicator(color: Colors.white))),
      ]),
    );
  }
}

/// Location message: a drawn map card with a pin; tap opens a map app.
class LocationCard extends StatelessWidget {
  const LocationCard({super.key, required this.lat, required this.lng});
  final double lat, lng;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final coords = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    return GestureDetector(
      onTap: () => launchUrl(
        Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng'),
        mode: LaunchMode.externalApplication,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 250,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 140,
              child: CustomPaint(
                painter: _MapPainter(dark: dark, seed: (lat * 1000 + lng * 1000).round()),
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 22),
                    child: Icon(Icons.location_on_rounded, size: 44, color: Brand.pomegranate, shadows: [Shadow(blurRadius: 6, color: Colors.black38)]),
                  ),
                ),
              ),
            ),
            Container(
              color: dark ? Colors.black26 : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Icon(Icons.map_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(context.tr('location'), style: const TextStyle(fontWeight: FontWeight.w700))),
                Directionality(textDirection: TextDirection.ltr, child: Text(coords, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.dark, required this.seed});
  final bool dark;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? const Color(0xFF22303D) : const Color(0xFFEAF0E6));
    final park = Paint()..color = dark ? const Color(0xFF253A2E) : const Color(0xFFCFE6C4);
    final water = Paint()..color = dark ? const Color(0xFF1D3550) : const Color(0xFFB9D7F2);
    canvas.drawCircle(Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height), 38, park);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(rnd.nextDouble() * size.width * 0.6, size.height * 0.65, 120, 60), const Radius.circular(30)), water);
    final road = Paint()
      ..color = dark ? const Color(0xFF3A4A5A) : Colors.white
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = dark ? const Color(0xFF2F3E4D) : const Color(0xFFFFFFFF)
      ..strokeWidth = 3;
    for (var i = 0; i < 6; i++) {
      final y = rnd.nextDouble() * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y + rnd.nextDouble() * 40 - 20), i < 2 ? road : minor);
      final x = rnd.nextDouble() * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x + rnd.nextDouble() * 40 - 20, size.height), i < 2 ? road : minor);
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter o) => o.dark != dark || o.seed != seed;
}

/// Shared contact card with "Message" / "Call" buttons.
class ContactCard extends StatelessWidget {
  const ContactCard({super.key, required this.meta, required this.onMessage});
  final Map<String, dynamic> meta;
  final void Function(String userId)? onMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (meta['name'] as String?) ?? '';
    final phone = meta['phone'] as String?;
    final email = meta['email'] as String?;
    final uid = meta['user_id'] as String?;
    return SizedBox(
      width: 240,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Brand.avatarColor(uid ?? name),
            child: Text(name.isEmpty ? '?' : name.characters.first, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              if (phone != null) Directionality(textDirection: TextDirection.ltr, child: Text(phone, style: TextStyle(color: cs.onSurfaceVariant))),
              if (email != null) Directionality(textDirection: TextDirection.ltr, child: Text(email, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5))),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        const Divider(height: 1),
        Row(children: [
          if (uid != null && onMessage != null)
            Expanded(child: TextButton(onPressed: () => onMessage!(uid), child: Text(context.tr('message')))),
          if (phone != null)
            Expanded(child: TextButton(onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}')), child: Text(context.tr('call_number')))),
        ]),
      ]),
    );
  }
}
