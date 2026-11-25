import 'dart:typed_data';

/// Browser: nothing is written to disk; a small in-memory cache only.
class CacheStore {
  final Map<String, Uint8List> _mem = {};
  final Map<String, Object?> _json = {};

  bool get persistent => false;
  Future<void> init() async {}

  String? filePath(String key) => null;
  Uint8List? memory(String key) => _mem[key];
  Future<Uint8List?> read(String key) async => _mem[key];
  bool exists(String key) => _mem.containsKey(key);

  Future<void> save(String key, Uint8List bytes) async {
    if (_mem.length > 200) _mem.remove(_mem.keys.first);
    _mem[key] = bytes;
  }

  Future<Map<String, int>> sizes() async => {for (final e in _mem.entries) e.key.split('/').first: e.value.length};
  Future<void> clear({String? folder}) async => folder == null ? _mem.clear() : _mem.removeWhere((k, _) => k.startsWith('$folder/'));
  Future<void> cleanup({required int keepDays, required int maxBytes}) async {}

  Future<void> writeJson(String name, Object data) async => _json[name] = data;
  Future<Object?> readJson(String name) async => _json[name];
  Future<void> clearJson(String prefix) async => _json.removeWhere((k, _) => k.startsWith(prefix));
}
