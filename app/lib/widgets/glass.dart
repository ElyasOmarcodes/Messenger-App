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
  static final ui.ImageFilter filter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14);

  /// Blur layer for a glass surface (inside a clip). Off → nothing is blurred.
  static Widget backdrop({required bool enabled, required Widget child}) => enabled ? BackdropFilter(filter: filter, child: child) : child;
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final button = Material(
      color: dark ? const Color(0xCC202B38) : const Color(0xCCEEF1F5),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: dark ? 0.08 : 0.6), width: 0.8),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
    return tooltip == null || onTap == null ? button : Tooltip(message: tooltip, child: button);
  }
}
