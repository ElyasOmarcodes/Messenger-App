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
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(s * 0.24));
      final paint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Brand.lapisBright, Brand.lapis, Brand.lapisDeep],
        ).createShader(rect);
      canvas.drawRRect(rrect, paint);
    }

    // Speech bubble
    final bubble = Path();
    final c = Offset(s * 0.5, s * 0.47);
    final r = s * (background ? 0.30 : 0.40);
    bubble.addOval(Rect.fromCircle(center: c, radius: r));
    // tail
    final tail = Path()
      ..moveTo(c.dx - r * 0.62, c.dy + r * 0.55)
      ..lineTo(c.dx - r * 0.95, c.dy + r * 1.18)
      ..lineTo(c.dx - r * 0.05, c.dy + r * 0.92)
      ..close();
    final full = Path.combine(PathOperation.union, bubble, tail);
    canvas.drawPath(
      full,
      Paint()..color = background ? Colors.white : Brand.lapis,
    );

    // Eight-pointed star
    final star = starPath(c, r * 0.62, r * 0.36, 8, rotation: math.pi / 8);
    canvas.drawPath(star, Paint()..color = Brand.accent);
    canvas.drawCircle(c, r * 0.16, Paint()..color = background ? Colors.white : Brand.lapis);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.background != background;
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? const Color(0xFF0A1020) : const Color(0xFFE9EEF8),
      child: CustomPaint(
        painter: _WallpaperPainter(
          color: dark ? const Color(0x14FFFFFF) : const Color(0x161F3F9E),
          accent: dark ? const Color(0x142E9BF0) : const Color(0x1A2E9BF0),
        ),
        child: child,
      ),
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter({required this.color, required this.accent});

  final Color color;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 72.0;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = accent;
    for (var y = -tile; y < size.height + tile; y += tile) {
      final row = (y / tile).round();
      for (var x = -tile; x < size.width + tile; x += tile) {
        final ox = row.isEven ? 0.0 : tile / 2;
        final c = Offset(x + ox, y);
        canvas.drawPath(starPath(c, 16, 9, 8, rotation: math.pi / 8), line);
        canvas.drawCircle(c, 3, fill);
        canvas.drawCircle(Offset(c.dx + tile / 2, c.dy + tile / 2), 2, fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter old) => old.color != color || old.accent != accent;
}
