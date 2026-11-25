import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Phones and desktop: media files in the app's cache folder (the system may
/// clear it when space runs out), chat data in the app's support folder.
/// Every file is named after its server path, one folder per chat, so we can
/// show how much space each chat uses and delete per chat.
class CacheStore {
  Directory? _media;
  Directory? _data;

  bool get persistent => true;

  Future<void> init() async {
    try {
      _media = Directory('${(await getApplicationCacheDirectory()).path}/paigham_media');
      _data = Directory('${(await getApplicationSupportDirectory()).path}/paigham_data');
      await _media!.create(recursive: true);
      await _data!.create(recursive: true);
    } catch (_) {}
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  File? _file(String key) {
    final m = _media;
    if (m == null) return null;
    final i = key.indexOf('/');
    final folder = i > 0 ? _safe(key.substring(0, i)) : 'misc';
    final name = _safe(i > 0 ? key.substring(i + 1) : key);
    return File('${m.path}/$folder/$name');
  }

  /// Path of a cached file (and marks it as just used), or null.
  String? filePath(String key) {
    final f = _file(key);
    if (f == null || !f.existsSync()) return null;
    try {
      f.setLastModifiedSync(DateTime.now()); // "last opened" for Keep Media
    } catch (_) {}
    return f.path;
  }

  Uint8List? memory(String key) => null;

  Future<Uint8List?> read(String key) async {
    final p = filePath(key);
    if (p == null) return null;
    try {
      return await File(p).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String key, Uint8List bytes) async {
    final f = _file(key);
    if (f == null) return;
    try {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
  }

  /// Bytes used per folder (= per chat).
  Future<Map<String, int>> sizes() async {
    final out = <String, int>{};
    final m = _media;
    if (m == null || !await m.exists()) return out;
    await for (final e in m.list(recursive: true, followLinks: false)) {
      if (e is File) {
        final rel = e.path.substring(m.path.length + 1);
        final folder = rel.split(Platform.pathSeparator).first;
        out[folder] = (out[folder] ?? 0) + await e.length();
      }
    }
    return out;
  }

  Future<void> clear({String? folder}) async {
    final m = _media;
    if (m == null) return;
    try {
      final d = folder == null ? m : Directory('${m.path}/${_safe(folder)}');
      if (await d.exists()) await d.delete(recursive: true);
      await m.create(recursive: true);
    } catch (_) {}
  }

  /// Telegram's "Keep Media": drop files not opened for [keepDays] days,
  /// then the least recently used ones until the cache fits [maxBytes].
  /// 0 means "forever" / "no limit".
  Future<void> cleanup({required int keepDays, required int maxBytes}) async {
    final m = _media;
    if (m == null || !await m.exists()) return;
    final files = <(File, DateTime, int)>[];
    await for (final e in m.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          files.add((e, await e.lastModified(), await e.length()));
        } catch (_) {}
      }
    }
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    var total = 0;
    final kept = <(File, DateTime, int)>[];
    for (final f in files) {
      if (keepDays > 0 && f.$2.isBefore(cutoff)) {
        await f.$1.delete().catchError((_) => f.$1);
      } else {
        kept.add(f);
        total += f.$3;
      }
    }
    if (maxBytes > 0 && total > maxBytes) {
      kept.sort((a, b) => a.$2.compareTo(b.$2)); // oldest first
      for (final f in kept) {
        if (total <= maxBytes) break;
        await f.$1.delete().catchError((_) => f.$1);
        total -= f.$3;
      }
    }
  }

  File? _json(String name) => _data == null ? null : File('${_data!.path}/${_safe(name)}.json');

  Future<void> writeJson(String name, Object data) async {
    final f = _json(name);
    if (f == null) return;
    try {
      await f.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<Object?> readJson(String name) async {
    final f = _json(name);
    if (f == null || !await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> clearJson(String prefix) async {
    final d = _data;
    if (d == null || !await d.exists()) return;
    await for (final e in d.list()) {
      if (e is File && e.uri.pathSegments.last.startsWith(_safe(prefix))) await e.delete().catchError((_) => e);
    }
  }
}
