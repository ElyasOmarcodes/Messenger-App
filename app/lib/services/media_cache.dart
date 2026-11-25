import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'cache_store.dart';

/// Local cache for photos, voice notes, avatars and chat data — the server
/// keeps the real copy (like Telegram's cloud), the phone keeps what it has
/// already seen so it opens instantly, uses less internet and works offline.
class MediaCache {
  MediaCache._();
  static final MediaCache instance = MediaCache._();

  final store = CacheStore();
  final Map<String, Future<Uint8List?>> _inflight = {};

  bool get persistent => store.persistent;
  Future<void> init() => store.init();

  /// Cached file on disk (phones/desktop), or null.
  String? filePath(String key) => store.filePath(key);
  bool has(String key) => store.filePath(key) != null || store.memory(key) != null;

  /// Bytes of [key]: from disk if we have them, otherwise downloaded once
  /// from [url] (asked for lazily) and saved.
  Future<Uint8List?> bytes(String key, Future<String?> Function() url) {
    return _inflight[key] ??= () async {
      try {
        final local = store.memory(key) ?? await store.read(key);
        if (local != null) return local;
        final u = await url();
        if (u == null) return null;
        final r = await http.get(Uri.parse(u));
        if (r.statusCode != 200) return null;
        await store.save(key, r.bodyBytes);
        return r.bodyBytes;
      } catch (_) {
        return null;
      } finally {
        unawaited(Future<void>.delayed(Duration.zero, () => _inflight.remove(key)));
      }
    }();
  }

  /// Key for a public link (avatars): folder "avatars", name from the link.
  static String urlKey(String url) => 'avatars/${url.hashCode.toUnsigned(32).toRadixString(16)}-${Uri.parse(url).pathSegments.last}';
}

/// An image that comes from the local cache, or is downloaded once and kept.
class CachedImage extends ImageProvider<CachedImage> {
  const CachedImage(this.cacheKey, this.url);

  /// Stable key (server path) — the signed link changes, the key does not.
  final String cacheKey;
  final Future<String?> Function() url;

  @override
  Future<CachedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: cacheKey);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final b = await MediaCache.instance.bytes(cacheKey, url);
    if (b == null || b.isEmpty) throw StateError('image not available');
    return decode(await ui.ImmutableBuffer.fromUint8List(b));
  }

  @override
  bool operator ==(Object other) => other is CachedImage && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
