import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../models/models.dart';

/// Round avatar: initials on a brand colour, or an icon for built-in chats.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.seed, required this.label, this.size = 52, this.kind});

  final String seed;
  final String label;
  final double size;
  final ChatKind? kind;

  String get _initials {
    final parts = label.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.characters.take(2).toString();
    return '${parts.first.characters.first}${parts[1].characters.first}';
  }

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case ChatKind.channel:
        return SizedBox.square(
          dimension: size,
          child: ClipOval(child: PaighamLogo(size: size)),
        );
      case ChatKind.bot:
        return _icon(Icons.smart_toy_rounded, const [Color(0xFF1E8C6E), Color(0xFF0F6B53)]);
      case ChatKind.saved:
        return _icon(Icons.bookmark_rounded, const [Brand.lapisBright, Brand.lapis]);
      case ChatKind.lobby:
        return _icon(Icons.public_rounded, const [Brand.saffron, Brand.saffronDeep], fg: Brand.ink);
      case ChatKind.group:
        return _icon(Icons.groups_rounded, [Brand.avatarColor(seed), Brand.avatarColor(seed)]);
      default:
        final c = Brand.avatarColor(seed);
        return Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color.lerp(c, Colors.white, 0.18)!, c],
            ),
          ),
          child: Text(
            _initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        );
    }
  }

  Widget _icon(IconData icon, List<Color> colors, {Color fg = Colors.white}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        ),
        child: Icon(icon, color: fg, size: size * 0.5),
      );
}
