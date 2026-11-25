import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Where Paigham keeps things on each system (like Telegram):
///
/// Android  /storage/emulated/0/Android/data/af.paigham.messenger/files/Paigham/
///            Paigham Images/[chat]/   Paigham Audio/[chat]/   Paigham Documents/[chat]/
///          …/cache/Paigham/           Avatars/  Stories/       (the system may clear it)
/// iPhone   Documents/Paigham/…  (shown in the Files app)      Caches/Paigham/…
/// Windows, macOS, Linux
///          Downloads/Paigham/[chat]/  for documents (like Telegram Desktop)
///          app data/Paigham/…         for photos, voice, avatars, stories
///
/// Chat data (lists, messages) stays in the app's private folder.
class CacheStore {
  Directory? _images, _audio, _docs, _cache, _data;

  bool get persistent => true;

  Future<void> init() async {
    try {
      Directory media;
      Directory cache;
      Directory docs;
      if (Platform.isAndroid) {
        final ext = await getExternalStorageDirectory(); // Android/data/[app]/files
        media = Directory('${(ext ?? await getApplicationSupportDirectory()).path}/Paigham');
        final extCache = await getExternalCacheDirectories();
        cache = Directory('${(extCache != null && extCache.isNotEmpty ? extCache.first : await getApplicationCacheDirectory()).path}/Paigham');
        docs = Directory('${media.path}/Paigham Documents');
      } else if (Platform.isIOS) {
        media = Directory('${(await getApplicationDocumentsDirectory()).path}/Paigham');
        cache = Directory('${(await getApplicationCacheDirectory()).path}/Paigham');
        docs = Directory('${media.path}/Paigham Documents');
      } else {
        media = Directory('${(await getApplicationSupportDirectory()).path}/Paigham');
        cache = Directory('${(await getApplicationCacheDirectory()).path}/Paigham');
        final dl = await getDownloadsDirectory();
        docs = Directory(dl != null ? '${dl.path}/Paigham' : '${media.path}/Paigham Documents');
      }
      _images = Directory('${media.path}/Paigham Images');
      _audio = Directory('${media.path}/Paigham Audio');
      _docs = docs;
      _cache = cache;
      _data = Directory('${(await getApplicationSupportDirectory()).path}/paigham_data');
      for (final d in [_images!, _audio!, _docs!, Directory('${cache.path}/Avatars'), Directory('${cache.path}/Stories'), _data!]) {
        await d.create(recursive: true);
      }
    } catch (_) {}
  }

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9._\-؀-ۿ ]'), '_');

  static const _imageExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'bmp'};
  static const _audioExt = {'m4a', 'webm', 'ogg', 'oga', 'opus', 'mp3', 'wav', 'aac', 'amr'};

  /// Folder for a key: "avatars/…", "stories/…" or "chat/time-name".
  File? _file(String key) {
    final i = key.indexOf('/');
    final head = i > 0 ? key.substring(0, i) : 'misc';
    final rest = i > 0 ? key.substring(i + 1) : key;
    if (head == 'avatars' && _cache != null) return File('${_cache!.path}/Avatars/${_safe(rest)}');
    if (head == 'stories' && _cache != null) return File('${_cache!.path}/Stories/${_safe(rest)}');
    final ext = rest.contains('.') ? rest.split('.').last.toLowerCase() : '';
    final root = _imageExt.contains(ext) ? _images : (_audioExt.contains(ext) ? _audio : _docs);
    if (root == null) return null;
    return File('${root.path}/${_safe(head)}/${_safe(rest)}');
  }

  List<Directory> get _chatRoots => [?_images, ?_audio, ?_docs];

  /// Path of a cached file (and marks it as just used), or null.
  String? filePath(String key) {
    final f = _file(key);
    if (f == null || !f.existsSync()) return null;
    try {
      f.setLastModifiedSync(DateTime.now()); // "last opened", for Keep Media
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

  Future<int> _dirSize(Directory d) async {
    var n = 0;
    if (!await d.exists()) return 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) n += await e.length().catchError((_) => 0);
    }
    return n;
  }

  /// Bytes used per chat (plus "avatars" and "stories").
  Future<Map<String, int>> sizes() async {
    final out = <String, int>{};
    for (final root in _chatRoots) {
      if (!await root.exists()) continue;
      await for (final e in root.list(followLinks: false)) {
        if (e is Directory) {
          final chat = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
          out[chat] = (out[chat] ?? 0) + await _dirSize(e);
        }
      }
    }
    if (_cache != null) {
      final a = await _dirSize(Directory('${_cache!.path}/Avatars'));
      final s = await _dirSize(Directory('${_cache!.path}/Stories'));
      if (a > 0) out['avatars'] = a;
      if (s > 0) out['stories'] = s;
    }
    return out;
  }

  Future<void> clear({String? folder}) async {
    try {
      final targets = <Directory>[];
      if (folder == null) {
        targets.addAll(_chatRoots);
        if (_cache != null) targets.addAll([Directory('${_cache!.path}/Avatars'), Directory('${_cache!.path}/Stories')]);
      } else if (folder == 'avatars' || folder == 'stories') {
        if (_cache != null) targets.add(Directory('${_cache!.path}/${folder == 'avatars' ? 'Avatars' : 'Stories'}'));
      } else {
        targets.addAll(_chatRoots.map((r) => Directory('${r.path}/${_safe(folder)}')));
      }
      for (final d in targets) {
        if (await d.exists()) await d.delete(recursive: true);
      }
      await init();
    } catch (_) {}
  }

  /// Telegram's "Keep Media": drop files not opened for [keepDays] days,
  /// then the least recently used ones until everything fits [maxBytes].
  /// 0 means "forever" / "no limit".
  Future<void> cleanup({required int keepDays, required int maxBytes}) async {
    final files = <(File, DateTime, int)>[];
    final roots = [..._chatRoots, ?_cache];
    for (final root in roots) {
      if (!await root.exists()) continue;
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            files.add((e, await e.lastModified(), await e.length()));
          } catch (_) {}
        }
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
      kept.sort((a, b) => a.$2.compareTo(b.$2)); // least recently opened first
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
      final tmp = File('${f.path}.part');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
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
