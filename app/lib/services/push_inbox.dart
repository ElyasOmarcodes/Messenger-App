import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

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
  static Future<void> put(String uid, String chatId, int keyId, SecretKey key, {bool now = false}) async {
    final m = await _load(uid);
    final id = '$chatId|$keyId';
    if (m.containsKey(id)) return;
    m[id] = E2E.b64(await key.extractBytes());
    Future<void> write() async {
      try {
        await _secure.write(key: _name, value: jsonEncode({'uid': uid, 'keys': m}));
      } catch (_) {}
    }

    _save?.cancel();
    if (now) return write();
    _save = Timer(const Duration(milliseconds: 500), write);
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
  static const sessionKey = 'push_session';

  /// The app's current access token, while still valid (never refreshed here).
  static Future<({String token, String uid})?> _session(SharedPreferences prefs) async {
    final raw = prefs.getString(sessionKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map;
      final exp = (j['exp'] as num?)?.toInt() ?? 0;
      if (exp * 1000 < DateTime.now().millisecondsSinceEpoch + 30000) return null;
      return (token: j['t'] as String, uid: j['uid'] as String);
    } catch (_) {
      return null;
    }
  }

  static Future<List<dynamic>?> _get(String path, String token) async {
    await AppConfig.load();
    final r = await http
        .get(Uri.parse('${AppConfig.supabaseUrl}/rest/v1/$path'), headers: {'apikey': AppConfig.supabaseAnonKey, 'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    return jsonDecode(r.body) as List<dynamic>;
  }

  /// The chat key when this phone does not hold it yet: its copy for me from
  /// the server, opened with my own key (kept in the Keystore). The wrapper's
  /// key must match the one pinned earlier (a server cannot swap it).
  static Future<SecretKey?> _fetchKey(SharedPreferences prefs, String token, String uid, String chat, int keyId) async {
    final rows = await _get('chat_keys?chat_id=eq.$chat&user_id=eq.$uid&key_id=eq.$keyId&select=wrapped,wrapped_by', token);
    if (rows == null || rows.isEmpty) return null;
    final row = rows.first as Map;
    final by = row['wrapped_by'] as String;
    if (!E2E.instance.ready && !await E2E.instance.loadLocal(uid)) return null;
    String? pub;
    if (by == uid) {
      pub = E2E.instance.publicKey;
    } else {
      final pins = jsonDecode(prefs.getString('key_pins_$uid') ?? '{}') as Map;
      final ks = await _get('user_keys?user_id=eq.$by&select=public_key', token);
      final server = ks == null || ks.isEmpty ? null : (ks.first as Map)['public_key'] as String?;
      pub = pins[by] as String?;
      if (pub == null || (server != null && server != pub)) return null; // unknown or changed: leave it to the app
    }
    if (pub == null) return null;
    final k = await E2E.instance.unwrap(row['wrapped'] as String, chatId: chat, keyId: keyId, wrapperPub: pub);
    if (k != null) await KeyVault.put(uid, chat, keyId, k, now: true);
    return k;
  }

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
    var cipher = d['cipher'] as String?;
    var keyId = int.tryParse('${d['key_id'] ?? ''}');
    if (d['plain'] != null) return row;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final uid = prefs.getString(uidKey);
    if (uid == null) return null;
    final ses = await _session(prefs);
    // the push came without the message (too big, or an older server
    // function): fetch it, like Telegram does with its push "hints"
    if ((cipher == null || cipher.isEmpty || keyId == null) && ses != null) {
      try {
        final rows = await _get('messages?id=eq.$id&select=*', ses.token);
        if (rows != null && rows.isNotEmpty) {
          final m = Map<String, dynamic>.from(rows.first as Map);
          if (m['cipher'] == null) {
            // a plain message (channel post, or from before encryption)
            return m;
          }
          cipher = m['cipher'] as String;
          keyId = (m['key_id'] as num?)?.toInt();
          for (final f in ['file_path', 'file_size', 'reply_to', 'created_at']) {
            if (m[f] != null) row[f] = m[f];
          }
        }
      } catch (_) {}
    }
    if (cipher == null || cipher.isEmpty || keyId == null) return null;
    var key = await KeyVault.get(uid, chat, keyId);
    if (key == null && ses != null) {
      try {
        key = await _fetchKey(prefs, ses.token, uid, chat, keyId);
      } catch (_) {}
    }
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
