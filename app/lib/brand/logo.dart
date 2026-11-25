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
    canvas.drawPath(
      starPath(c, r * 0.56, r * 0.32, 8, rotation: math.pi / 8),
      Paint()..color = background ? Brand.blue : Colors.white,
    );
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

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The pattern lives in its own layer, so scrolling messages never redraws it.
    return ColoredBox(
      color: dark ? Brand.nightChatBg : Brand.lightChatBg,
      child: Stack(children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: false,
              painter: _WallpaperPainter(
                color: dark ? const Color(0x0FFFFFFF) : const Color(0x1A3390EC),
                accent: dark ? const Color(0x142E9BF0) : const Color(0x1A2E9BF0),
              ),
            ),
          ),
        ),
        Positioned.fill(child: RepaintBoundary(child: child)),
      ]),
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
