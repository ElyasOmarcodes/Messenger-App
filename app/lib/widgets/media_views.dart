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

/// Hero tag shared by a photo in a bubble and the same photo in the viewer.
Object photoHeroTag(({String? path, Uint8List? bytes}) item) => item.path != null ? 'photo:${item.path}' : 'photo-local:${identityHashCode(item.bytes)}';

/// Loads a private attachment (or shows local bytes while uploading).
/// The picture is decoded at the size it is shown, not at full camera size,
/// and the link is fetched once, so scrolling stays smooth.
class AttachmentImage extends StatefulWidget {
  const AttachmentImage({super.key, this.path, this.bytes, this.fit = BoxFit.cover, this.full = false});
  final String? path;
  final Uint8List? bytes;
  final BoxFit fit;

  /// Full-screen viewer: decode at screen size.
  final bool full;

  @override
  State<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<AttachmentImage> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(AttachmentImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  void _resolve() {
    final p = widget.path;
    if (p == null) return;
    final app = AppScope.read(context);
    _url = app.cachedFileUrl(p);
    if (_url == null) {
      app.fileUrl(p).then((u) {
        if (mounted && u != null && widget.path == p) setState(() => _url = u);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(color: Colors.black12);
    return LayoutBuilder(
      builder: (context, c) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final w = c.hasBoundedWidth ? c.maxWidth : MediaQuery.sizeOf(context).width;
        final h = c.hasBoundedHeight ? c.maxHeight : MediaQuery.sizeOf(context).height;
        // decode just big enough to cover the box (cover) or fit the screen (viewer)
        final px = ((widget.full ? math.max(w, h) : math.max(w, h)) * dpr).clamp(64, 2400).round();
        if (widget.bytes != null) {
          return Image.memory(widget.bytes!, fit: widget.fit, gaplessPlayback: true, cacheWidth: px);
        }
        if (_url == null) return placeholder;
        return Image(
          image: ResizeImage.resizeIfNeeded(px, null, NetworkImage(_url!)),
          fit: widget.fit,
          gaplessPlayback: true,
          frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : placeholder,
          errorBuilder: (_, _, _) => Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined)),
        );
      },
    );
  }
}

/// Full-screen, swipeable photo viewer. Opens like Telegram: the photo grows
/// out of the bubble, the black backdrop fades in, the bars slide in from the
/// top and bottom edges. Swipe up or down to close.
class GalleryViewer extends StatefulWidget {
  const GalleryViewer({super.key, required this.items, this.initial = 0});
  final List<({String? path, Uint8List? bytes})> items;
  final int initial;

  static void open(BuildContext context, List<({String? path, Uint8List? bytes})> items, int i) => Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => GalleryViewer(items: items, initial: i),
    ),
  );

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late int _i = widget.initial;
  late final _ctl = PageController(initialPage: widget.initial);
  final _zoom = TransformationController();
  bool _bars = true;
  bool _zoomed = false;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _zoom.addListener(() {
      final z = _zoom.value.getMaxScaleOnAxis() > 1.01;
      if (z != _zoomed) setState(() => _zoomed = z);
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final p = widget.items[_i].path;
    if (p == null) return;
    final url = await AppScope.read(context).fileUrl(p);
    if (url != null) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context)!.animation!;
    final pad = MediaQuery.paddingOf(context);
    final dragFade = (1 - _drag.abs() / 400).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: route,
      builder: (context, _) {
        final t = Curves.easeOut.transform(route.value);
        final barsT = _bars ? t * dragFade : 0.0;
        return Stack(
          children: [
            // black backdrop
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withValues(alpha: t * dragFade)),
            ),
            // photos
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _bars = !_bars),
                onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
                onVerticalDragEnd: _zoomed
                    ? null
                    : (d) {
                        if (_drag.abs() > 110 || (d.primaryVelocity ?? 0).abs() > 900) {
                          Navigator.of(context).pop();
                        } else {
                          setState(() => _drag = 0);
                        }
                      },
                child: Transform.translate(
                  offset: Offset(0, _drag),
                  child: PageView.builder(
                    controller: _ctl,
                    physics: _zoomed ? const NeverScrollableScrollPhysics() : null,
                    itemCount: widget.items.length,
                    onPageChanged: (i) => setState(() {
                      _i = i;
                      _zoom.value = Matrix4.identity();
                    }),
                    itemBuilder: (_, i) => InteractiveViewer(
                      transformationController: i == _i ? _zoom : null,
                      maxScale: 5,
                      panEnabled: _zoomed,
                      child: Center(
                        child: Hero(
                          tag: photoHeroTag(widget.items[i]),
                          child: AttachmentImage(path: widget.items[i].path, bytes: widget.items[i].bytes, fit: BoxFit.contain, full: true),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // top bar slides down from the edge
            Positioned(
              left: 0,
              right: 0,
              top: -80 * (1 - barsT),
              child: Opacity(
                opacity: barsT,
                child: Container(
                  padding: EdgeInsets.only(top: pad.top),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Color(0x00000000)]),
                  ),
                  child: SizedBox(
                    height: 56,
                    child: Row(
                      children: [
                        const BackButton(color: Colors.white),
                        Expanded(
                          child: Text(
                            context.digits('${_i + 1} / ${widget.items.length}'),
                            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('download'),
                          onPressed: _download,
                          icon: const Icon(Icons.download_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // bottom strip slides up from the edge
            if (widget.items.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: -80 * (1 - barsT),
                child: Opacity(
                  opacity: barsT,
                  child: Container(
                    padding: EdgeInsets.fromLTRB(12, 16, 12, 12 + pad.bottom),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0x99000000), Color(0x00000000)]),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var k = 0; k < widget.items.length; k++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: k == _i ? 18 : 7,
                            height: 7,
                            decoration: BoxDecoration(color: k == _i ? Colors.white : Colors.white54, borderRadius: BorderRadius.circular(4)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
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
      for (var i = 0; i < n; i++) (path: i < items.length ? items[i]['path'] as String? : null, bytes: local != null && i < local.length ? local[i] : null),
    ];
    Widget tile(int i, double w, double h) => GestureDetector(
      onTap: () => GalleryViewer.open(context, all, i),
      child: SizedBox(
        width: w,
        height: h,
        child: Hero(
          tag: photoHeroTag(all[i]),
          child: AttachmentImage(path: all[i].path, bytes: all[i].bytes),
        ),
      ),
    );
    const g = 2.0;
    final rows = <Widget>[];
    if (n == 2) {
      rows.add(
        Row(
          children: [
            tile(0, (width - g) / 2, 170),
            const SizedBox(width: g),
            tile(1, (width - g) / 2, 170),
          ],
        ),
      );
    } else if (n == 3) {
      final big = width * 0.62, side = width - big - g;
      rows.add(
        Row(
          children: [
            tile(0, big, 240),
            const SizedBox(width: g),
            Column(
              children: [
                tile(1, side, (240 - g) / 2),
                const SizedBox(height: g),
                tile(2, side, (240 - g) / 2),
              ],
            ),
          ],
        ),
      );
    } else {
      // first row: 2 tiles; remaining rows: up to 3 tiles each
      final half = (width - g) / 2;
      rows.add(
        Row(
          children: [
            tile(0, half, 150),
            const SizedBox(width: g),
            tile(1, half, 150),
          ],
        ),
      );
      for (var i = 2; i < n; i += 3) {
        final count = math.min(3, n - i);
        final w = (width - g * (count - 1)) / count;
        rows.add(const SizedBox(height: g));
        rows.add(
          Row(
            children: [
              for (var k = 0; k < count; k++) ...[if (k > 0) const SizedBox(width: g), tile(i + k, w, 110)],
            ],
          ),
        );
      }
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Column(mainAxisSize: MainAxisSize.min, children: rows),
          if (message.pending)
            const Positioned.fill(
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            ),
        ],
      ),
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
      onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=16/$lat/$lng'), mode: LaunchMode.externalApplication),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 140,
                child: CustomPaint(
                  painter: _MapPainter(dark: dark, seed: (lat * 1000 + lng * 1000).round()),
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: 22),
                      child: Icon(
                        Icons.location_on_rounded,
                        size: 44,
                        color: Brand.pomegranate,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                color: dark ? Colors.black26 : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.map_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(context.tr('location'), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(coords, style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(rnd.nextDouble() * size.width * 0.6, size.height * 0.65, 120, 60), const Radius.circular(30)),
      water,
    );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Brand.avatarColor(uid ?? name),
                child: Text(
                  name.isEmpty ? '?' : name.characters.first,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    if (phone != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(phone, style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    if (email != null)
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: Text(email, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Row(
            children: [
              if (uid != null && onMessage != null)
                Expanded(
                  child: TextButton(onPressed: () => onMessage!(uid), child: Text(context.tr('message'))),
                ),
              if (phone != null)
                Expanded(
                  child: TextButton(onPressed: () => launchUrl(Uri.parse('tel:${phone.replaceAll(' ', '')}')), child: Text(context.tr('call_number'))),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
