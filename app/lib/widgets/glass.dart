import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// iOS / Telegram style "glass": a strong blur of what is behind plus a
/// saturation boost (colours glow through, like Apple's materials), a light
/// tint and a thin bright rim. All glass on a screen shares one backdrop
/// (see [BackdropGroup] in main.dart), which is much cheaper than separate blurs.
class Glass {
  Glass._();

  static const double _s = 1.7; // saturation
  static const _lr = 0.2126, _lg = 0.7152, _lb = 0.0722;

  static final ui.ImageFilter filter = ui.ImageFilter.compose(
    outer: const ColorFilter.matrix(<double>[
      _lr * (1 - _s) + _s, _lg * (1 - _s), _lb * (1 - _s), 0, 0, //
      _lr * (1 - _s), _lg * (1 - _s) + _s, _lb * (1 - _s), 0, 0, //
      _lr * (1 - _s), _lg * (1 - _s), _lb * (1 - _s) + _s, 0, 0, //
      0, 0, 0, 1, 0,
    ]),
    inner: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22, tileMode: TileMode.mirror),
  );

  /// Blur layer for a glass surface (inside a clip). Off → nothing is blurred.
  static Widget backdrop({required bool enabled, required Widget child}) => enabled ? BackdropFilter.grouped(filter: filter, child: child) : child;
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
