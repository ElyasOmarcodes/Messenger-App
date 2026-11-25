import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'glass.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Soft edge under the header / above the input bar, like Telegram: content
// fades out gradually into the page colour and is softly blurred right behind
// the bar. Only ONE light backdrop blur is used (cheap on phones); its edge
// sits under an almost-opaque part of the fade, so no hard line is visible.
// ─────────────────────────────────────────────────────────────────────────────
class SoftEdge extends StatelessWidget {
  const SoftEdge({super.key, required this.fromTop, required this.color, this.solid = 0, this.blur = true});

  /// True: the bar is at the top (fade goes down). False: bar at the bottom.
  final bool fromTop;
  final Color color;

  /// Height (px) right behind the bar that is blurred and almost opaque.
  final double solid;
  final bool blur;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.maxHeight;
          final s = h <= 0 ? 0.0 : (solid / h).clamp(0.0, 0.95);
          final begin = fromTop ? Alignment.topCenter : Alignment.bottomCenter;
          final end = fromTop ? Alignment.bottomCenter : Alignment.topCenter;
          return Stack(
            children: [
              if (blur && solid > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: fromTop ? 0 : null,
                  bottom: fromTop ? null : 0,
                  height: solid,
                  child: ClipRect(
                    child: BackdropFilter(filter: Glass.filter, child: const SizedBox.expand()),
                  ),
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: begin,
                      end: end,
                      colors: [
                        color.withValues(alpha: 0.94),
                        color.withValues(alpha: 0.82),
                        color.withValues(alpha: 0.45),
                        color.withValues(alpha: 0.12),
                        color.withValues(alpha: 0),
                      ],
                      stops: [0, s, s + (1 - s) * 0.4, s + (1 - s) * 0.75, 1],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bubble shape. Messages from the same person sent close together form a
// group: the first has a big top corner, the middle ones are tight on the
// sender side, the last gets a big bottom corner and the tail.
// ─────────────────────────────────────────────────────────────────────────────
enum GroupPos { single, first, middle, last }

const double kBubbleTail = 7;

class BubblePainter extends CustomPainter {
  BubblePainter({required this.color, required this.tailOnRight, required this.pos, this.border});
  final Color color;
  final bool tailOnRight;
  final GroupPos pos;
  final Color? border;

  static const big = 18.0, small = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final hasTail = pos == GroupPos.single || pos == GroupPos.last;
    final top = pos == GroupPos.single || pos == GroupPos.first ? big : small;
    final bottom = hasTail ? 0.0 : small;
    final l = tailOnRight ? 0.0 : kBubbleTail, r = tailOnRight ? size.width - kBubbleTail : size.width;
    final rect = Rect.fromLTRB(l, 0, r, size.height);
    final rr = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(tailOnRight ? big : top),
      topRight: Radius.circular(tailOnRight ? top : big),
      bottomLeft: Radius.circular(tailOnRight ? big : bottom),
      bottomRight: Radius.circular(tailOnRight ? bottom : big),
    );
    var path = Path()..addRRect(rr);
    if (hasTail) {
      final h = size.height;
      final tail = Path();
      if (tailOnRight) {
        tail
          ..moveTo(r - 14, h)
          ..lineTo(r, h - 14)
          ..quadraticBezierTo(r, h - 3, size.width, h)
          ..close();
      } else {
        tail
          ..moveTo(l + 14, h)
          ..lineTo(l, h - 14)
          ..quadraticBezierTo(l, h - 3, 0, h)
          ..close();
      }
      path = Path.combine(PathOperation.union, path, tail);
    }
    canvas.drawShadow(path, Colors.black, 0.6, false);
    canvas.drawPath(path, Paint()..color = color);
    if (border != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = border!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6,
      );
    }
  }

  @override
  bool shouldRepaint(covariant BubblePainter o) => o.color != color || o.tailOnRight != tailOnRight || o.pos != pos || o.border != border;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dust: on delete the bubble breaks into particles that drift away and fade
// (a sweep across the bubble, like Telegram's delete animation).
// ─────────────────────────────────────────────────────────────────────────────
class Dissolvable extends StatefulWidget {
  const Dissolvable({super.key, required this.child});
  final Widget child;

  @override
  State<Dissolvable> createState() => DissolvableState();
}

class DissolvableState extends State<Dissolvable> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  List<_Particle>? _particles;
  bool _gone = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  /// Plays the effect; completes when the bubble has vanished.
  Future<void> dissolve() async {
    if (_particles != null) return;
    final ro = _boundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    try {
      const ratio = 1.0;
      final img = await ro.toImage(pixelRatio: ratio);
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return;
      final w = img.width, h = img.height;
      final rnd = math.Random();
      final ps = <_Particle>[];
      const step = 3;
      final bytes = data.buffer.asUint8List();
      for (var y = 0; y < h; y += step) {
        for (var x = 0; x < w; x += step) {
          final o = (y * w + x) * 4;
          final a = bytes[o + 3];
          if (a < 40) continue;
          ps.add(
            _Particle(
              x: x.toDouble(),
              y: y.toDouble(),
              color: Color.fromARGB(a, bytes[o], bytes[o + 1], bytes[o + 2]),
              delay: (x / w) * 0.45 + rnd.nextDouble() * 0.12,
              dx: (rnd.nextDouble() * 1.4 - 0.3) * 40,
              dy: -(rnd.nextDouble() * 50 + 10),
            ),
          );
        }
      }
      img.dispose();
      setState(() => _particles = ps);
      await _ctl.forward();
      if (mounted) setState(() => _gone = true);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ps = _particles;
    // Normal case: just a repaint boundary (cheap, and lets the bubble be cached).
    if (ps == null) return RepaintBoundary(key: _boundary, child: widget.child);
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      child: _gone
          ? const SizedBox(width: double.infinity)
          : Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: 0,
                  child: RepaintBoundary(key: _boundary, child: widget.child),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _ctl,
                      builder: (_, _) => CustomPaint(painter: _DustPainter(ps, _ctl.value, Directionality.of(context))),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Particle {
  _Particle({required this.x, required this.y, required this.color, required this.delay, required this.dx, required this.dy});
  final double x, y, delay, dx, dy;
  final Color color;
}

class _DustPainter extends CustomPainter {
  _DustPainter(this.ps, this.t, this.dir);
  final List<_Particle> ps;
  final double t;
  final TextDirection dir;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    final flip = dir == TextDirection.rtl;
    for (final q in ps) {
      final local = ((t - (flip ? 0.57 - q.delay : q.delay)) / 0.45).clamp(0.0, 1.0);
      if (local >= 1) continue;
      final e = Curves.easeOut.transform(local);
      final x = q.x + q.dx * e * (flip ? -1 : 1);
      final y = q.y + q.dy * e;
      p.color = q.color.withValues(alpha: q.color.a * (1 - local));
      final s = 3.0 * (1 - local * 0.5);
      canvas.drawRect(Rect.fromLTWH(x, y, s, s), p);
    }
  }

  @override
  bool shouldRepaint(covariant _DustPainter o) => o.t != t;
}
