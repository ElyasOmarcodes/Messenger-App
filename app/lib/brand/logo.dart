import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'brand.dart';

/// The Paigham mark: a speech bubble carrying an eight-pointed star, the
/// geometric star found in Afghan tile work from Herat to Mazar.
class PaighamLogo extends StatelessWidget {
  const PaighamLogo({super.key, this.size = 96, this.background = true});

  final double size;

  /// When true the mark sits on a rounded lapis tile (app icon style).
  final bool background;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LogoPainter(background: background)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.background});

  final bool background;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (background) {
      final rect = Offset.zero & size;
      canvas.drawPath(
        squirclePath(rect),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6CC3FF), Brand.blue, Color(0xFF2468D8)],
          ).createShader(rect),
      );
    }
    final ink = background ? Colors.white : Brand.blue;
    final c = Offset(s * 0.5, s * 0.48);
    final r = s * (background ? 0.27 : 0.40);
    // Rounded speech bubble with a soft tail.
    final bubble = Path()..addOval(Rect.fromCircle(center: c, radius: r));
    final tail = Path()
      ..moveTo(c.dx - r * 0.70, c.dy + r * 0.40)
      ..quadraticBezierTo(c.dx - r * 0.86, c.dy + r * 1.02, c.dx - r * 1.08, c.dy + r * 1.12)
      ..quadraticBezierTo(c.dx - r * 0.46, c.dy + r * 1.12, c.dx - r * 0.10, c.dy + r * 0.90)
      ..close();
    canvas.drawPath(Path.combine(PathOperation.union, bubble, tail), Paint()..color = ink);
    // Eight-pointed star (Afghan tile motif).
    canvas.drawPath(starPath(c, r * 0.56, r * 0.32, 8, rotation: math.pi / 8), Paint()..color = background ? Brand.blue : Colors.white);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.background != background;
}

/// Samsung One UI style "squircle" (superellipse, n = 5).
Path squirclePath(Rect r, {double n = 5}) {
  final path = Path();
  final a = r.width / 2, b = r.height / 2, cx = r.center.dx, cy = r.center.dy;
  for (var i = 0; i <= 120; i++) {
    final t = i / 120 * 2 * math.pi;
    final ct = math.cos(t), st = math.sin(t);
    final x = cx + a * ct.sign * math.pow(ct.abs(), 2 / n);
    final y = cy + b * st.sign * math.pow(st.abs(), 2 / n);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  return path..close();
}

Path starPath(Offset c, double outer, double inner, int points, {double rotation = 0}) {
  final path = Path();
  final step = math.pi / points;
  for (var i = 0; i < points * 2; i++) {
    final rad = i.isEven ? outer : inner;
    final a = -math.pi / 2 + rotation + i * step;
    final p = Offset(c.dx + rad * math.cos(a), c.dy + rad * math.sin(a));
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// Subtle tiled star lattice used as the chat wallpaper.
class GirihWallpaper extends StatelessWidget {
  const GirihWallpaper({super.key, required this.child});

  final Widget child;

  /// Width of one pattern tile in logical pixels: the doodles keep the same
  /// physical size on every phone, tablet and desktop (no stretching).
  static const double tile = 420;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Soft gradient like Telegram's themes, with the doodles drawn over it.
    final colors = dark ? const [Color(0xFF0F1B2A), Color(0xFF0B1420), Color(0xFF121F2E)] : const [Color(0xFFCFE2F3), Color(0xFFDCE9E2), Color(0xFFD5E3F5)];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: Stack(
        children: [
          // The pattern lives in its own cached layer, so scrolling never redraws it.
          Positioned.fill(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: const AssetImage('assets/wallpaper/doodle.png'),
                    repeat: ImageRepeat.repeat,
                    alignment: Alignment.topLeft,
                    scale: 1024 / tile,
                    filterQuality: FilterQuality.medium,
                    colorFilter: ColorFilter.mode(dark ? const Color(0x17FFFFFF) : const Color(0x262B5278), BlendMode.srcIn),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: RepaintBoundary(child: child)),
        ],
      ),
    );
  }
}
