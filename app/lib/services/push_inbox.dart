import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'e2e.dart';

/// How a push becomes a readable notification and an instant message, the
/// way WhatsApp and Signal do it with end-to-end encryption:
///
/// * the server puts the *encrypted* message into the push (it cannot read it);
/// * the phone opens it with the chat key it already holds ([KeyVault], kept
///   in the Android Keystore / iOS Keychain) and shows sender + text;
/// * the opened message is written to the phone ([PushInbox]), so the chat
///   list and the chat show it the moment the app opens, before any network.
class KeyVault {
  KeyVault._();
  static const _secure = FlutterSecureStorage();
  static const _name = 'paigham_chat_keys';

  static Map<String, String>? _cache; // "chat|keyId" → base64 key
  static String? _uid;
  static Timer? _save;

  static Future<Map<String, String>> _load(String uid) async {
    if (_cache != null && _uid == uid) return _cache!;
    _uid = uid;
    _cache = {};
    try {
      final raw = await _secure.read(key: _name);
      if (raw != null) {
        final j = jsonDecode(raw) as Map;
        if (j['uid'] == uid) _cache = Map<String, String>.from(j['keys'] as Map);
      }
    } catch (_) {}
    return _cache!;
  }

  /// Remember a chat key (called whenever the app opens or makes one).
  static Future<void> put(String uid, String chatId, int keyId, SecretKey key) async {
    final m = await _load(uid);
    final id = '$chatId|$keyId';
    if (m.containsKey(id)) return;
    m[id] = E2E.b64(await key.extractBytes());
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _secure.write(key: _name, value: jsonEncode({'uid': uid, 'keys': m}));
      } catch (_) {}
    });
  }

  static Future<SecretKey?> get(String uid, String chatId, int keyId) async {
    final b = (await _load(uid))['$chatId|$keyId'];
    return b == null ? null : SecretKey(E2E.unb64(b));
  }

  static Future<void> clear() async {
    _cache = null;
    _uid = null;
    try {
      await _secure.delete(key: _name);
    } catch (_) {}
  }
}

/// Messages that arrived by push while the app was away, already opened.
class PushInbox {
  PushInbox._();
  static const _k = 'push_inbox';
  static const uidKey = 'push_uid';

  /// From a push's data: the opened message row (same shape as the server's),
  /// or null when it cannot be opened here.
  static Future<Map<String, dynamic>?> open(Map<String, dynamic> d) async {
    final id = d['message_id'] as String?, chat = d['chat_id'] as String?, sender = d['sender_id'] as String?;
    if (id == null || chat == null || sender == null) return null;
    final row = <String, dynamic>{
      'id': id,
      'chat_id': chat,
      'sender_id': sender,
      'kind': d['kind'] ?? 'text',
      'body': d['plain'] ?? '',
      'created_at': d['created_at'] ?? DateTime.now().toUtc().toIso8601String(),
    };
    final cipher = d['cipher'] as String?;
    final keyId = int.tryParse('${d['key_id'] ?? ''}');
    if (cipher == null || cipher.isEmpty || keyId == null) return (d['plain'] != null) ? row : null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final uid = prefs.getString(uidKey);
    if (uid == null) return null;
    final key = await KeyVault.get(uid, chat, keyId);
    if (key == null) return null;
    final p = await E2E.instance.open(key, cipher, chatId: chat, msgId: id, senderId: sender, keyId: keyId);
    if (p == null) return null;
    row['key_id'] = keyId;
    row['body'] = p['b'] ?? '';
    if (p['m'] != null) row['meta'] = p['m'];
    if (p['fn'] != null) row['file_name'] = p['fn'];
    if (p['mt'] != null) row['mime_type'] = p['mt'];
    if (p['d'] != null) row['duration_ms'] = p['d'];
    return row;
  }

  static Future<void> add(Map<String, dynamic> row) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = prefs.getStringList(_k) ?? [];
    list.add(jsonEncode(row));
    // a phone away for days: keep the newest few hundred
    await prefs.setStringList(_k, list.length > 300 ? list.sublist(list.length - 300) : list);
  }

  /// Takes everything waiting (the app calls this when it opens or returns).
  static Future<List<Map<String, dynamic>>> take() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final list = prefs.getStringList(_k) ?? const [];
    if (list.isEmpty) return const [];
    await prefs.remove(_k);
    return [
      for (final s in list)
        if (jsonDecode(s) case final Map m) Map<String, dynamic>.from(m),
    ];
  }
}
