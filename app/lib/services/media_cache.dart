import 'dart:async';
import 'dart:typed_data' show BytesBuilder;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'cache_store.dart';

/// Local cache for photos, voice notes, avatars and chat data — the server
/// keeps the real copy (like Telegram's cloud), the phone keeps what it has
/// already seen so it opens instantly, uses less internet and works offline.
class MediaCache extends ChangeNotifier {
  MediaCache._();
  static final MediaCache instance = MediaCache._();

  final store = CacheStore();
  final Map<String, Future<Uint8List?>> _inflight = {};
  final Map<String, ValueNotifier<double>> _progress = {};
  final Map<String, http.Client> _clients = {};

  /// Download progress (0…1) of [key] while it is being downloaded, else null.
  ValueListenable<double>? progressOf(String key) => _progress[key];
  bool isDownloading(String key) => _progress.containsKey(key);

  /// Runs on every downloaded file before it is kept (opens encrypted files).
  Future<Uint8List?> Function(String key, Uint8List raw)? transform;

  /// Stops a download (the X on the progress ring).
  void cancel(String key) => _clients.remove(key)?.close();

  bool get persistent => store.persistent;
  Future<void> init() => store.init();

  /// Cached file on disk (phones/desktop), or null.
  String? filePath(String key) => store.filePath(key);
  bool has(String key) => store.exists(key);

  /// Bytes of [key]: from disk if we have them, otherwise downloaded once
  /// from [url] (asked for lazily) and saved.
  Future<Uint8List?> bytes(String key, Future<String?> Function() url) {
    return _inflight[key] ??= () async {
      try {
        final local = store.memory(key) ?? await store.read(key);
        if (local != null) return local;
        final prog = _progress[key] = ValueNotifier(0);
        final client = _clients[key] = http.Client();
        notifyListeners();
        final u = await url();
        if (u == null) return null;
        // streamed, so the ring shows how much has arrived
        final r = await client.send(http.Request('GET', Uri.parse(u)));
        if (r.statusCode != 200) return null;
        final total = r.contentLength ?? 0;
        final out = BytesBuilder(copy: false);
        await for (final chunk in r.stream) {
          out.add(chunk);
          if (total > 0) prog.value = (out.length / total).clamp(0.0, 1.0);
        }
        var b = out.takeBytes();
        if (total > 0 && b.length < total) return null; // cut off
        if (transform != null) {
          final t = await transform!(key, b);
          if (t == null) return null;
          b = t;
        }
        await store.save(key, b);
        return b;
      } catch (_) {
        return null;
      } finally {
        _clients.remove(key)?.close();
        final p = _progress.remove(key);
        if (p != null) {
          notifyListeners();
          // let rings that still listen finish their frame first
          unawaited(Future<void>.delayed(const Duration(seconds: 1), p.dispose));
        }
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
