import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../services/media_cache.dart';

/// Round avatar: initials on a brand colour, or a group icon.
/// Decode sizes in steps, so an avatar that grows or shrinks in an
/// animation is not decoded again on every frame.
int _bucket(double px) => ((px / 64).ceil() * 64).clamp(64, 1024);

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
        child: Image(
          // kept on the phone after the first download
          image: ResizeImage(CachedImage(MediaCache.urlKey(imageUrl!), () async => imageUrl), width: _bucket(size * MediaQuery.devicePixelRatioOf(context))),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
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
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(c, Colors.white, 0.18)!, c]),
      ),
      child: group
          ? Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.52)
          : Text(
              _initials,
              style: TextStyle(color: Colors.white, fontSize: size * 0.36, fontWeight: FontWeight.w700, height: 1.1),
            ),
    );
  }
}

/// Blue bookmark circle used for "Saved Messages".
class SavedAvatar extends StatelessWidget {
  const SavedAvatar({super.key, this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.blueBright, Brand.blue]),
    ),
    child: Icon(Icons.bookmark_rounded, color: Colors.white, size: size * 0.5),
  );
}

/// Grey archive circle used for the "Archived chats" row.
class ArchiveAvatar extends StatelessWidget {
  const ArchiveAvatar({super.key, this.size = 52});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF9AA6B2)),
    child: Icon(Icons.archive_rounded, color: Colors.white, size: size * 0.48),
  );
}
