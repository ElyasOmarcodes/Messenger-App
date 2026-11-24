import 'package:flutter/material.dart';

import '../brand/brand.dart';

/// Round avatar: initials on a brand colour, or a group icon.
class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.seed, required this.label, this.size = 52, this.group = false, this.imageUrl});

  final String seed;
  final String label;
  final double size;
  final bool group;
  final String? imageUrl;

  String get _initials {
    final parts = label.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '؟';
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return '${parts.first.characters.first}${parts[1].characters.first}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = Brand.avatarColor(seed);
    if (imageUrl != null) {
      return ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Avatar(seed: seed, label: label, size: size, group: group),
        ),
      );
    }
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
      child: group
          ? Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.52)
          : Text(_initials,
              style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w700, height: 1.1)),
    );
  }
}
