import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// iOS / Telegram style "glass": a strong blur of what is behind plus a
/// saturation boost (colours glow through, like Apple's materials), a light
/// tint and a thin bright rim. Used only on small surfaces (tab bar, menus):
/// live blur behind large areas is costly on Android.
class Glass {
  Glass._();

  /// A plain, light blur. (A saturation boost on top doubled the work, and a
  /// shared "grouped" backdrop measured 1.8–3× slower on Android/Impeller.)
  /// iOS 27 "Liquid Glass" values (seunghan91/ios27-design-system): a low
  /// blur (sigma 6) — also far cheaper to draw than a strong one.
  static final ui.ImageFilter filter = ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.mirror);

  /// Blur layer for a glass surface (inside a clip). Off → nothing is blurred.
  static Widget backdrop({required bool enabled, required Widget child}) => enabled ? BackdropFilter(filter: filter, child: child) : child;
}

/// iOS 27 Liquid Glass surface: light blur of what is behind, a 70% tint,
/// a soft highlight from above, a bright rim that catches the light at the
/// corners, and a soft shadow. Off (Settings → glass) → the same shape, solid.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({super.key, required this.child, this.radius = 24, this.circle = false, this.padding, this.shadow = true, this.tint});
  final Widget child;
  final double radius;
  final bool circle;
  final EdgeInsetsGeometry? padding;
  final bool shadow;
  final Color? tint;

  static Color fillOf(bool dark, bool glass, [Color? tint]) {
    final base = tint ?? (dark ? const Color(0xFF1B2430) : Colors.white);
    return base.withValues(alpha: glass ? 0.70 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = GlassScope.of(context);
    final fill = fillOf(dark, glass, tint);
    final r = circle ? null : BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: r,
        // light from above
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.45],
          colors: [
            Color.alphaBlend(Colors.white.withValues(alpha: dark ? 0.06 : 0.28), fill),
            fill,
          ],
        ),
      ),
      child: CustomPaint(
        foregroundPainter: _RimPainter(circle: circle, radius: radius, dark: dark),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
    if (glass) body = BackdropFilter(filter: Glass.filter, child: body);
    body = circle ? ClipOval(child: body) : ClipRRect(borderRadius: r!, child: body);
    if (!shadow) return body;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.30 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: body,
    );
  }
}

/// The glass rim: bright where the light hits (top-left and bottom-right), faint between.
class _RimPainter extends CustomPainter {
  _RimPainter({required this.circle, required this.radius, required this.dark});
  final bool circle, dark;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final a = dark ? [0.32, 0.05, 0.16] : [0.95, 0.30, 0.70];
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [for (final x in a) Colors.white.withValues(alpha: x)],
        stops: const [0, 0.5, 1],
      ).createShader(rect);
    if (circle) {
      canvas.drawOval(rect, p);
    } else {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), p);
    }
  }

  @override
  bool shouldRepaint(_RimPainter o) => o.dark != dark || o.radius != radius || o.circle != circle;
}

/// Whether glass is on (Settings → Chat settings → glass effect).
class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.enabled, required super.child});
  final bool enabled;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<GlassScope>()?.enabled ?? true;

  @override
  bool updateShouldNotify(GlassScope old) => old.enabled != enabled;
}

/// A rounded glass panel.
class GlassBox extends StatelessWidget {
  const GlassBox({super.key, required this.child, this.radius = 24, this.enabled = true, this.tint, this.padding});
  final Widget child;
  final double radius;
  final bool enabled;
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = tint ?? (dark ? const Color(0xFF1E2934) : Colors.white);
    final fill = base.withValues(alpha: enabled ? (dark ? 0.62 : 0.58) : 1);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Glass.backdrop(
        enabled: enabled,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            // light from above: a little brighter at the top
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(Colors.white.withValues(alpha: dark ? 0.07 : 0.30), fill),
                fill,
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: dark ? 0.16 : 0.75), width: 0.9),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Round, see-through bar button (the same style as the buttons on the
/// profile photo): back, call, video, more.
class RoundBarButton extends StatelessWidget {
  const RoundBarButton({super.key, required this.icon, this.onTap, this.tooltip, this.size = 42});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = LiquidGlass(
      circle: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
    return tooltip == null || onTap == null ? button : Tooltip(message: tooltip, child: button);
  }
}
