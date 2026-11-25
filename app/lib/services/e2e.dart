import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// End-to-end encryption for Paigham.
///
/// * Every user has an X25519 key pair. The private key stays on the phone
///   (Android Keystore / iOS Keychain through flutter_secure_storage); the
///   public key is published.
/// * Every chat has a random AES-256 key. A copy of it is locked for each
///   member with a key made from X25519(sender, member) + HKDF-SHA256, so only
///   members can open it. A new chat key is made when someone leaves.
/// * Messages are AES-256-GCM sealed with the chat key; the message id, chat,
///   sender and key number are bound in as associated data, so the server can
///   neither read nor move or re-attribute a message.
/// * Files get their own random AES-256-GCM key, carried inside the sealed
///   message; the server only stores ciphertext.
/// * The private key is backed up locked with the user's PIN through
///   Argon2id (memory-hard), so a new phone can restore it; the PIN never
///   leaves the phone.
class E2E {
  E2E._();
  static final E2E instance = E2E._();

  static final _x = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const _secure = FlutterSecureStorage();
  static final _rnd = Random.secure();

  SimpleKeyPair? _kp;
  String? _uid;

  /// This phone's public key (base64), once the keys are ready.
  String? publicKey;

  bool get ready => _kp != null;

  static Uint8List randomBytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _rnd.nextInt(256)));
  static String b64(List<int> b) => base64Encode(b);
  static Uint8List unb64(String s) => base64Decode(s);

  String _store(String uid) => 'paigham_e2e_$uid';

  Future<void> _use(String uid, List<int> seed) async {
    _uid = uid;
    _kp = await _x.newKeyPairFromSeed(seed);
    publicKey = b64((await _kp!.extractPublicKey()).bytes);
  }

  /// Key already on this phone?
  Future<bool> loadLocal(String uid) async {
    _uid = uid;
    try {
      final s = await _secure.read(key: _store(uid));
      if (s == null) return false;
      await _use(uid, unb64(s));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// First time: a new key pair, locked with [pin] for the backup.
  Future<Map<String, dynamic>> create(String uid, String pin) async {
    final seed = randomBytes(32);
    final backup = await _lock(uid, seed, pin);
    await _secure.write(key: _store(uid), value: b64(seed));
    await _use(uid, seed);
    return backup;
  }

  /// New phone: open the backup with [pin]. False = wrong PIN.
  Future<bool> restore(String uid, Map<String, dynamic> backup, String pin) async {
    try {
      final salt = unb64(backup['salt'] as String);
      final key = await _kdf(pin, salt, backup);
      final box = SecretBox.fromConcatenation(unb64(backup['box'] as String), nonceLength: 12, macLength: 16);
      final seed = await _aes.decrypt(box, secretKey: key, aad: utf8.encode('paigham-backup-v1|$uid'));
      await _secure.write(key: _store(uid), value: b64(seed));
      await _use(uid, seed);
      return true;
    } on SecretBoxAuthenticationError {
      return false;
    }
  }

  /// Lock this phone's key again with a new PIN (change PIN).
  Future<Map<String, dynamic>?> relock(String pin) async {
    if (_kp == null || _uid == null) return null;
    return _lock(_uid!, await _kp!.extractPrivateKeyBytes(), pin);
  }

  /// Signed out: the key leaves this phone (the locked backup stays).
  Future<void> forget() async {
    final uid = _uid;
    _kp = null;
    publicKey = null;
    _uid = null;
    if (uid != null) {
      try {
        await _secure.delete(key: _store(uid));
      } catch (_) {}
    }
  }

  // Argon2id: memory-hard, so guessing PINs is slow even on big hardware.
  // Web runs it in JavaScript, so it uses lighter settings there.
  static Map<String, int> get _params => kIsWeb ? {'m': 19456, 't': 2, 'p': 1} : {'m': 65536, 't': 3, 'p': 1};

  static const _common = {
    '12345678',
    '123456789',
    '1234567890',
    '87654321',
    'password',
    'password1',
    'passw0rd',
    'qwerty123',
    'qwertyui',
    'abc12345',
    'abcd1234',
    '1q2w3e4r',
    '1qaz2wsx',
    'iloveyou',
    'paigham1',
    'paigham123',
    'afghanistan',
    'kabul123',
    '11223344',
    '12341234',
    '00000000',
    'aa123456',
    'a1234567',
    '123456aa',
    'asdf1234',
    'zxcv1234',
    '123qwe123',
  };

  /// Why a PIN is too weak to guard the backup, or null if it is fine.
  ///
  /// If the server is broken into, the locked backups can be guessed at
  /// offline, so the PIN must be long enough that guessing takes ages even
  /// with Argon2id: 8+ characters with letters and digits, or 12+ of anything.
  static String? pinProblem(String pin) {
    if (pin.length < 8) return 'pin_short';
    final letters = RegExp(r'[^\d\s]').hasMatch(pin), digits = RegExp(r'\d').hasMatch(pin);
    if (pin.length < 12 && !(letters && digits)) return 'pin_weak';
    if (_common.contains(pin.toLowerCase()) || RegExp(r'^(.)\1+$').hasMatch(pin)) return 'pin_weak';
    if (RegExp(r'^(.{1,4})\1+$').hasMatch(pin)) return 'pin_weak'; // abcabcabc, 12121212
    return null;
  }

  Future<SecretKey> _kdf(String pin, List<int> salt, Map<String, dynamic> p) => Argon2id(
    parallelism: (p['p'] as num).toInt(),
    memory: (p['m'] as num).toInt(),
    iterations: (p['t'] as num).toInt(),
    hashLength: 32,
  ).deriveKeyFromPassword(password: pin, nonce: salt);

  Future<Map<String, dynamic>> _lock(String uid, List<int> seed, String pin) async {
    final salt = randomBytes(16);
    final params = _params;
    final key = await _kdf(pin, salt, params);
    final box = await _aes.encrypt(seed, secretKey: key, nonce: randomBytes(12), aad: utf8.encode('paigham-backup-v1|$uid'));
    return {'v': 1, 'kdf': 'argon2id', ...params, 'salt': b64(salt), 'box': b64(box.concatenation())};
  }

  // ── Chat keys ─────────────────────────────────────────────────────────────
  Future<SecretKey> newChatKey() async => SecretKey(randomBytes(32));

  Future<SecretKey> _pairKey(String otherPub, String chatId) async {
    final shared = await _x.sharedSecretKey(
      keyPair: _kp!,
      remotePublicKey: SimplePublicKey(unb64(otherPub), type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(secretKey: shared, nonce: utf8.encode('paigham/chat/$chatId'), info: utf8.encode('paigham-wrap-v1'));
  }

  /// A copy of [chatKey] that only [recipientId] (owner of [recipientPub]) can open.
  Future<String> wrap(SecretKey chatKey, {required String chatId, required int keyId, required String recipientId, required String recipientPub}) async {
    final k = await _pairKey(recipientPub, chatId);
    final box = await _aes.encrypt(
      await chatKey.extractBytes(),
      secretKey: k,
      nonce: randomBytes(12),
      aad: utf8.encode('paigham-wrap-v1|$chatId|$keyId|$recipientId'),
    );
    return b64(box.concatenation());
  }

  /// Opens a copy locked for me by the owner of [wrapperPub].
  Future<SecretKey?> unwrap(String wrapped, {required String chatId, required int keyId, required String wrapperPub}) async {
    if (_kp == null) return null;
    try {
      final k = await _pairKey(wrapperPub, chatId);
      final box = SecretBox.fromConcatenation(unb64(wrapped), nonceLength: 12, macLength: 16);
      final raw = await _aes.decrypt(box, secretKey: k, aad: utf8.encode('paigham-wrap-v1|$chatId|$keyId|$_uid'));
      return SecretKey(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Messages ──────────────────────────────────────────────────────────────
  static List<int> _msgAad(String chatId, String msgId, String senderId, int keyId) => utf8.encode('paigham-msg-v1|$chatId|$msgId|$senderId|$keyId');

  Future<String> seal(
    SecretKey key,
    Map<String, dynamic> payload, {
    required String chatId,
    required String msgId,
    required String senderId,
    required int keyId,
  }) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(payload)), secretKey: key, nonce: randomBytes(12), aad: _msgAad(chatId, msgId, senderId, keyId));
    return b64(box.concatenation());
  }

  Future<Map<String, dynamic>?> open(
    SecretKey key,
    String cipher, {
    required String chatId,
    required String msgId,
    required String senderId,
    required int keyId,
  }) async {
    try {
      final box = SecretBox.fromConcatenation(unb64(cipher), nonceLength: 12, macLength: 16);
      final clear = await _aes.decrypt(box, secretKey: key, aad: _msgAad(chatId, msgId, senderId, keyId));
      return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
    } catch (_) {
      return null;
    }
  }

  // ── Files ─────────────────────────────────────────────────────────────────
  /// A fresh key for one file (base64).
  static String newFileKey() => b64(randomBytes(32));

  static Future<Uint8List> sealFile(Uint8List bytes, String fileKey) async {
    final box = await _aes.encrypt(bytes, secretKey: SecretKey(unb64(fileKey)), nonce: randomBytes(12));
    return box.concatenation();
  }

  static Future<Uint8List?> openFile(Uint8List data, String fileKey) async {
    try {
      final box = SecretBox.fromConcatenation(data, nonceLength: 12, macLength: 16, copy: false);
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(unb64(fileKey))));
    } catch (_) {
      return null;
    }
  }

  // ── Safety number ─────────────────────────────────────────────────────────
  /// 60 digits both people see the same; if they match, no one is in between.
  static Future<String> safetyNumber(String pubA, String pubB) async {
    final keys = [pubA, pubB]..sort();
    final h = await Sha512().hash(utf8.encode('paigham-safety-v1|${keys[0]}|${keys[1]}'));
    final b = h.bytes;
    final groups = <String>[];
    for (var i = 0; i < 12; i++) {
      // plain arithmetic (not bit shifts) so it gives the same digits on the web
      var n = 0;
      for (var j = 0; j < 5; j++) {
        n = (n * 256 + b[i * 5 + j]) % 100000;
      }
      groups.add(n.toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }
}
