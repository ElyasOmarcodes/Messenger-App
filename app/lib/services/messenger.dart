import 'package:flutter/foundation.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../widgets/rich_message.dart';
import 'e2e.dart';
import 'media_cache.dart';
import 'notifier.dart';
import 'push.dart';
import 'push_inbox.dart';

/// Result of an auth call: null on success, otherwise a translation key.
typedef AuthError = String?;

/// Central app state: account, chats, messages, realtime and settings.
/// Backend: Supabase (Postgres + Auth + Realtime + Storage).
/// Where this phone is with its end-to-end key.
enum KeyState { unknown, ready, needCreate, needRestore, needStrengthen, offline, unsupported }

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  late SharedPreferences _prefs;
  bool ready = false;

  AppLang lang = AppLang.ps;
  ThemeMode themeMode = ThemeMode.system;

  /// Glass (blur) effects; can be turned off on slow phones, like Telegram.
  bool glass = false;

  /// The notifications page was shown once (Android); web / iPhone skip it.
  bool get notifyAsked => kIsWeb || defaultTargetPlatform != TargetPlatform.android || (_prefs.getBool('notify_asked') ?? false);
  void setNotifyAsked() {
    _prefs.setBool('notify_asked', true);
    notifyListeners();
  }

  // ── Storage (like Telegram's "Data and storage") ──────────────────────────
  /// Delete media not opened for this many days (0 = keep forever).
  int keepDays = 30;

  /// Largest cache size in MB (0 = no limit).
  int maxCacheMb = 3072;

  /// Download photos automatically; otherwise they show a download button.
  bool autoPhotos = true;

  /// Data saver (weak or costly internet): smaller photos when sending,
  /// photos download on tap, lower-resolution video calls.
  bool dataSaver = false;

  void setDataSaver(bool v) {
    dataSaver = v;
    _prefs.setBool('data_saver', v);
    if (v) setAutoPhotos(false);
    notifyListeners();
  }

  /// Longest side and JPEG quality for photos we send (Telegram sends 1280 px).
  ({double side, int quality}) get photoLimits => dataSaver ? (side: 1024, quality: 68) : (side: 1280, quality: 82);

  void setKeepDays(int d) {
    keepDays = d;
    _prefs.setInt('keep_days', d);
    notifyListeners();
    unawaited(cleanCache());
  }

  void setMaxCache(int mb) {
    maxCacheMb = mb;
    _prefs.setInt('max_cache_mb', mb);
    notifyListeners();
    unawaited(cleanCache());
  }

  void setAutoPhotos(bool v) {
    autoPhotos = v;
    _prefs.setBool('auto_photos', v);
    notifyListeners();
  }

  Future<void> cleanCache() => MediaCache.instance.store.cleanup(keepDays: keepDays, maxBytes: maxCacheMb * 1024 * 1024);

  String get _cachePrefix => 'u_${myId ?? 'none'}';

  // ── Offline copy: everything seen is kept on the phone ───────────────────
  final Map<String, Timer> _saveTimers = {};

  /// Saves a chat's messages (and the chat list) a moment after a change.
  void _persistSoon(String chatId) {
    _saveTimers[chatId]?.cancel();
    _saveTimers[chatId] = Timer(const Duration(milliseconds: 800), () {
      final list = _messages[chatId];
      if (list != null) {
        final keep = [
          for (final m in list)
            if (!m.pending && !m.id.startsWith('local-')) m,
        ];
        final tail = keep.length > 300 ? keep.sublist(keep.length - 300) : keep;
        unawaited(MediaCache.instance.store.writeJson('${_cachePrefix}_m_$chatId', [for (final m in tail) m.toJson()]));
      }
      _persistChatsSoon();
    });
  }

  Timer? _chatsTimer;
  void _persistChatsSoon() {
    _chatsTimer?.cancel();
    _chatsTimer = Timer(const Duration(milliseconds: 800), () {
      if (myId == null || chats.isEmpty) return;
      unawaited(MediaCache.instance.store.writeJson('${_cachePrefix}_chats', [for (final c in chats) c.toJson()]));
    });
  }

  SupabaseClient get _sb => Supabase.instance.client;
  Session? get session => AppConfig.configured ? _sb.auth.currentSession : null;
  String? get myId => session?.user.id;
  String get myEmail => session?.user.email ?? '';

  Profile? me;
  List<Chat> chats = [];
  bool chatsLoaded = false;
  final Map<String, List<Message>> _messages = {};
  final Map<String, String> _signedUrls = {};
  String? openChatId;
  bool realtimeOnline = false;

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  Timer? _reloadTimer;
  final _incoming = StreamController<Message>.broadcast();

  /// Messages from other people (for in-app banners).
  Stream<Message> get incoming => _incoming.stream;

  Strings get s => Strings(lang);

  /// True while the app is visible; otherwise new messages raise a system notification.
  bool foreground = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final was = foreground;
    foreground = state == AppLifecycleState.resumed;
    if (foreground && !was && myId != null) {
      // back in the app: fetch at once and clear the notifications it read
      _reloadTimer?.cancel();
      // first what pushes already brought (instant), then the server
      unawaited(_drainInbox().whenComplete(reloadChats));
      unawaited(_drain());
      unawaited(Notifier.instance.cancelAll());
    }
    _presence(); // online now / last seen when leaving
  }

  // ── Presence: "online" while the app is open, else "last seen …" ─────────
  Timer? _beat;

  void _presence() {
    _beat?.cancel();
    if (myId == null) return;
    unawaited(_touch());
    if (foreground) _beat = Timer.periodic(const Duration(seconds: 60), (_) => _touch());
  }

  Future<void> _touch() async {
    try {
      await _sb.rpc('touch_presence').timeout(_net);
    } catch (_) {}
  }

  /// Fresh "last seen" of one person (the open chat's header asks every minute).
  Future<void> refreshPresence(Chat chat) async {
    final peer = chat.isGroup ? null : chat.peer(myId ?? '');
    if (peer == null) return;
    try {
      final row = await _sb.from('profiles').select('last_seen').eq('id', peer.id).maybeSingle().timeout(_net);
      final v = row?['last_seen'] as String?;
      if (v == null) return;
      final i = chat.members.indexWhere((m) => m.id == peer.id);
      if (i < 0) return;
      final m = chat.members[i];
      final seen = DateTime.parse(v).toLocal();
      if (m.lastSeen == seen) return;
      chat.members[i] = Profile(
        id: m.id,
        email: m.email,
        displayName: m.displayName,
        username: m.username,
        avatarPath: m.avatarPath,
        lastReadAt: m.lastReadAt,
        role: m.role,
        rights: m.rights,
        lastSeen: seen,
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    avatarBaseUrl = '${AppConfig.supabaseUrl}/storage/v1/object/public/avatars';
    _prefs = await SharedPreferences.getInstance();
    lang = AppLang.fromCode(_prefs.getString('lang'));
    themeMode = ThemeMode.values.byName(_prefs.getString('theme') ?? 'system');
    // light by default (no live blur); v0.16 resets the old default
    glass = false; // Telegram Android look: no glass
    keepDays = _prefs.getInt('keep_days') ?? 30;
    maxCacheMb = _prefs.getInt('max_cache_mb') ?? 3072;
    autoPhotos = _prefs.getBool('auto_photos') ?? true;
    dataSaver = _prefs.getBool('data_saver') ?? false;
    await MediaCache.instance.init();
    // encrypted files are opened right after they are downloaded
    MediaCache.instance.transform = _openDownloaded;
    // Telegram's "Keep Media": old, unopened files are removed in the background.
    unawaited(Future<void>.delayed(const Duration(seconds: 8), cleanCache));
    if (AppConfig.configured) {
      _authSub = _sb.auth.onAuthStateChange.listen((st) {
        // the current pass for the push handler (it never refreshes it itself:
        // two places refreshing one session would sign the user out)
        final ses = st.session;
        if (ses != null) {
          unawaited(_prefs.setString(PushInbox.sessionKey, jsonEncode({'t': ses.accessToken, 'exp': ses.expiresAt, 'uid': ses.user.id})));
        } else if (st.event == AuthChangeEvent.signedOut) {
          unawaited(_prefs.remove(PushInbox.sessionKey));
        }
        if (st.event == AuthChangeEvent.signedIn || st.event == AuthChangeEvent.initialSession) {
          if (st.session != null && me == null) _onSignedIn();
        } else if (st.event == AuthChangeEvent.signedOut) {
          _onSignedOut();
        }
        notifyListeners();
      });
    }
    ready = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  // ── Auth ─────────────────────────────────────────────────────────────────
  String _authError(Object e) {
    if (e is AuthException) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid login')) return 'err_login';
      if (m.contains('expired') || m.contains('otp') || m.contains('token')) return 'err_code';
      if (m.contains('already') || m.contains('registered')) return 'err_exists';
      if (m.contains('password')) return 'err_password';
      if (m.contains('email')) return 'err_email';
    }
    final t = e.toString().toLowerCase();
    if (t.contains('socket') || t.contains('network') || t.contains('failed host') || t.contains('xmlhttprequest') || t.contains('clientexception')) {
      return 'err_network';
    }
    return 'err_generic';
  }

  /// 'new', 'unconfirmed' or 'active' (decides which sign-in page comes next).
  Future<String?> emailStatus(String email) async {
    try {
      return await _sb.rpc('email_status', params: {'e': email.trim().toLowerCase()}) as String;
    } catch (e) {
      return null;
    }
  }

  /// Creates the account; the server emails a 6-digit code.
  Future<AuthError> signUp(String name, String email, String password) async {
    try {
      final res = await _sb.auth.signUp(email: email.trim().toLowerCase(), password: password, data: {'display_name': name.trim()});
      // With email confirmation on, an existing address returns a user without identities.
      if (res.user != null && (res.user!.identities?.isEmpty ?? false)) return 'err_exists';
      return null;
    } catch (e) {
      return _authError(e);
    }
  }

  Future<AuthError> verifySignup(String email, String code) async {
    try {
      await _sb.auth.verifyOTP(type: OtpType.signup, email: email.trim().toLowerCase(), token: code.trim());
      return null;
    } catch (e) {
      return _authError(e) == 'err_network' ? 'err_network' : 'err_code';
    }
  }

  Future<AuthError> resendSignup(String email) async {
    try {
      await _sb.auth.resend(type: OtpType.signup, email: email.trim().toLowerCase());
      return null;
    } catch (e) {
      return _authError(e);
    }
  }

  /// Returns 'unconfirmed' when the email still needs its code.
  Future<AuthError> signIn(String email, String password) async {
    try {
      await _sb.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
      return null;
    } on AuthException catch (e) {
      if (e.message.toLowerCase().contains('not confirmed')) return 'unconfirmed';
      return _authError(e);
    } catch (e) {
      return _authError(e);
    }
  }

  Future<AuthError> sendResetCode(String email) async {
    try {
      await _sb.auth.resetPasswordForEmail(email.trim().toLowerCase());
      return null;
    } catch (e) {
      return _authError(e);
    }
  }

  Future<AuthError> resetPassword(String email, String code, String newPassword) async {
    try {
      await _sb.auth.verifyOTP(type: OtpType.recovery, email: email.trim().toLowerCase(), token: code.trim());
    } catch (e) {
      return _authError(e) == 'err_network' ? 'err_network' : 'err_code';
    }
    try {
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } catch (e) {
      return _authError(e);
    }
  }

  Future<void> signOut() async {
    await Push.stop();
    // a signed-out phone keeps no one's chats, and not the key either
    await MediaCache.instance.store.clearJson(_cachePrefix);
    await E2E.instance.forget();
    await KeyVault.clear();
    await _prefs.remove(PushInbox.uidKey);
    await PushInbox.take();
    _chatKeys.clear();
    _sendKeys.clear();
    keyState = KeyState.unknown;
    await _sb.auth.signOut();
  }

  Future<void> _onSignedIn() async {
    // Everything saved on the phone first, before any network call, so the
    // app opens fully (chats, stories, unsent messages) without internet.
    final cachedMe = await MediaCache.instance.store.readJson('${_cachePrefix}_me');
    if (cachedMe is Map<String, dynamic> && me == null) me = Profile.fromJson(cachedMe);
    final cached = await MediaCache.instance.store.readJson('${_cachePrefix}_chats');
    if (cached is List && chats.isEmpty) {
      try {
        chats = cached.map((e) => Chat.fromJson(e as Map<String, dynamic>)).toList();
        _sortChats();
        chatsLoaded = true;
      } catch (_) {}
    }
    await _prefs.setString(PushInbox.uidKey, myId!);
    await _drainInbox(); // what pushes brought while the app was closed
    await _loadCachedStories();
    await _loadOutbox();
    _showOutboxInChats();
    notifyListeners();
    await _initKeys();
    _subscribe();
    _presence();
    unawaited(_loadProfile());
    unawaited(loadStories());
    await reloadChats();
    unawaited(_drain());
  }

  // ── End-to-end encryption ────────────────────────────────────────────────
  KeyState keyState = KeyState.unknown;
  Map<String, dynamic>? _backup;
  final Map<String, Map<int, SecretKey>> _chatKeys = {};
  final Map<String, Future<void>> _keyLoads = {};
  final Map<String, ({int id, SecretKey key, DateTime at})> _sendKeys = {};
  final Map<String, String> _pubs = {};

  /// Server has the v9 update (sealed stories, reactions, old messages).
  bool _v9 = false;

  /// Keys registered for downloaded files (stories, quotes): cache key → file key.
  final Map<String, String> _fileKeys = {};

  /// Public keys seen before (trust on first use, like Signal): userId → key.
  /// A key that changes later is NOT used until the person is checked.
  final Map<String, String> _pins = {};

  /// People whose key changed since we first saw it: userId → new key.
  final Map<String, String> keyChanges = {};

  void registerFileKey(String cacheKey, String? fileKey) {
    if (fileKey != null) _fileKeys[cacheKey] = fileKey;
  }

  // kept in preferences (also on the web, and kept after signing out)
  Future<void> _loadPins() async {
    _pins.clear();
    final raw = _prefs.getString('key_pins_${myId!}');
    if (raw == null) return;
    try {
      _pins.addAll((jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as String)));
    } catch (_) {}
  }

  void _savePins() => unawaited(_prefs.setString('key_pins_${myId!}', jsonEncode(_pins)));

  /// May [pub] be used as [uid]'s key? Mine must be exactly mine; someone
  /// else's must match the key we saw first (a server cannot swap it).
  bool _trusted(String uid, String pub) {
    if (uid == myId) return pub == E2E.instance.publicKey;
    final pinned = _pins[uid];
    if (pinned == null) {
      _pins[uid] = pub;
      _savePins();
      return true;
    }
    if (pinned == pub) return true;
    if (keyChanges[uid] != pub) {
      keyChanges[uid] = pub;
      notifyListeners();
    }
    return false;
  }

  /// The key to open things [uid] locked: never a key the server swapped in,
  /// but the one we saw first (so a swap can neither read nor block old messages).
  String? _trustedPub(String uid, String? serverPub) {
    if (uid == myId) return E2E.instance.publicKey;
    if (serverPub == null) return _pins[uid];
    return _trusted(uid, serverPub) ? serverPub : _pins[uid];
  }

  /// "Accept" on the key-changed notice (after checking the safety number).
  Future<void> acceptKeyChange(String uid) async {
    final pub = keyChanges.remove(uid);
    if (pub == null) return;
    _pins[uid] = pub;
    _savePins();
    _sendKeys.clear();
    await _keysChanged();
  }

  /// Members of [chat] whose key changed.
  List<String> keyChangedIn(Chat chat) => [
    for (final m in chat.members)
      if (keyChanges.containsKey(m.id)) m.id,
  ];

  /// Who may hold this chat's key: in a one-to-one chat only the two people
  /// (a server cannot slip in a third), in Saved Messages only me.
  bool _mayHold(String chatId, String uid) {
    final chat = chatById(chatId);
    if (chat == null || chat.isGroup) return true;
    if (chat.isSaved) return uid == myId;
    if (uid == myId) return true;
    final peer = chat.peer(myId ?? '');
    return peer != null && peer.id == uid;
  }

  Future<void> _probeV9() async {
    try {
      await _sb.rpc('story_audience').timeout(_net);
      _v9 = true;
      unawaited(_resealOld());
    } catch (_) {
      _v9 = false;
    }
  }

  /// Key on this phone? Otherwise: is there a locked backup to restore?
  Future<void> _initKeys() async {
    await _loadPins();
    if (await E2E.instance.loadLocal(myId!)) {
      keyState = KeyState.ready;
      unawaited(_publishKey());
      unawaited(_probeV9());
      return;
    }
    await checkKeyBackup();
  }

  Future<void> checkKeyBackup() async {
    try {
      final row = await _sb.from('key_backups').select('data').eq('user_id', myId!).maybeSingle().timeout(_net);
      _backup = row == null ? null : Map<String, dynamic>.from(row['data'] as Map);
      keyState = _backup == null ? KeyState.needCreate : KeyState.needRestore;
    } on PostgrestException catch (e) {
      // the server has no encryption tables yet (database update v8 not run):
      // keep working as before instead of locking everyone out
      keyState = e.code == 'PGRST205' || e.code == '42P01' ? KeyState.unsupported : KeyState.offline;
    } catch (_) {
      keyState = KeyState.offline;
    }
    notifyListeners();
  }

  Future<void> _publishKey() async {
    final pub = E2E.instance.publicKey;
    if (pub == null) return;
    try {
      await _sb.from('user_keys').upsert({'user_id': myId, 'public_key': pub, 'updated_at': DateTime.now().toUtc().toIso8601String()}).timeout(_net);
    } catch (_) {}
  }

  /// First time (or "forgot PIN"): a new key, locked with [pin] as a backup.
  /// Returns a translation key on failure.
  Future<String?> createKeys(String pin) async {
    final weak = E2E.pinProblem(pin);
    if (weak != null) return weak;
    try {
      final backup = await E2E.instance.create(myId!, pin);
      await _sb.from('key_backups').upsert({'user_id': myId, 'data': backup, 'updated_at': DateTime.now().toUtc().toIso8601String()}).timeout(_net);
      await _sb
          .from('user_keys')
          .upsert({'user_id': myId, 'public_key': E2E.instance.publicKey, 'updated_at': DateTime.now().toUtc().toIso8601String()})
          .timeout(_net);
    } catch (_) {
      await E2E.instance.forget(); // no key without its backup
      return 'err_network';
    }
    _backup = null;
    await _keysChanged();
    return null;
  }

  /// New phone: open the backup with the PIN.
  Future<String?> restoreKeys(String pin) async {
    final b = _backup;
    if (b == null) return 'err_generic';
    if (!await E2E.instance.restore(myId!, b, pin)) return 'wrong_pin';
    await _publishKey();
    await _keysChanged();
    if (E2E.pinProblem(pin) != null) {
      // an old short PIN: make a stronger one before going on
      keyState = KeyState.needStrengthen;
      notifyListeners();
    }
    return null;
  }

  Future<String?> changePin(String pin) async {
    final weak = E2E.pinProblem(pin);
    if (weak != null) return weak;
    final backup = await E2E.instance.relock(pin);
    if (backup == null) return 'err_generic';
    try {
      await _sb.from('key_backups').upsert({'user_id': myId, 'data': backup, 'updated_at': DateTime.now().toUtc().toIso8601String()}).timeout(_net);
      if (keyState == KeyState.needStrengthen) {
        keyState = KeyState.ready;
        notifyListeners();
      }
      return null;
    } catch (_) {
      return 'err_network';
    }
  }

  Future<void> _keysChanged() async {
    keyState = KeyState.ready;
    unawaited(_probeV9());
    _chatKeys.clear();
    _sendKeys.clear();
    notifyListeners();
    // messages that could not be opened before
    for (final id in _messages.keys.toList()) {
      if (_messages[id]!.any((m) => m.locked)) {
        _messages[id]!.removeWhere((m) => m.locked);
        unawaited(loadMessages(id));
      }
    }
    await reloadChats();
    unawaited(_drain());
  }

  Future<String?> _pubOf(String uid) async {
    final c = _pubs[uid];
    if (c != null) return c;
    final row = await _sb.from('user_keys').select('public_key').eq('user_id', uid).maybeSingle().timeout(_net);
    final k = row?['public_key'] as String?;
    if (k != null) _pubs[uid] = k;
    return k;
  }

  /// Opens my copies of the chat keys ([chatId] = one chat, null = all chats).
  Future<void> _loadMyChatKeys([String? chatId]) async {
    if (!E2E.instance.ready) return;
    try {
      var q = _sb.from('chat_keys').select('chat_id,key_id,wrapped,wrapped_by').eq('user_id', myId!);
      if (chatId != null) q = q.eq('chat_id', chatId);
      final rows = await q.timeout(_net);
      final need = {for (final r in rows) r['wrapped_by'] as String}..removeWhere(_pubs.containsKey);
      if (need.isNotEmpty) {
        final ks = await _sb.from('user_keys').select('user_id,public_key').inFilter('user_id', need.toList()).timeout(_net);
        for (final k in ks) {
          _pubs[k['user_id'] as String] = k['public_key'] as String;
        }
      }
      for (final r in rows) {
        final c = r['chat_id'] as String, id = (r['key_id'] as num).toInt();
        if (_chatKeys[c]?[id] != null) continue;
        final by = r['wrapped_by'] as String;
        final pub = _trustedPub(by, _pubs[by]);
        if (pub == null) continue;
        final k = await E2E.instance.unwrap(r['wrapped'] as String, chatId: c, keyId: id, wrapperPub: pub);
        if (k != null) _rememberKey(c, id, k);
      }
    } catch (_) {
      // offline: the messages stay locked until the next try
    }
  }

  /// Keeps a chat key in memory and in the phone's key store, so a push can
  /// be opened (and shown with its text) even when the app is closed.
  void _rememberKey(String chatId, int keyId, SecretKey k) {
    _chatKeys.putIfAbsent(chatId, () => {})[keyId] = k;
    final me = myId;
    if (me != null) unawaited(KeyVault.put(me, chatId, keyId, k));
  }

  Future<SecretKey?> _keyFor(String chatId, int keyId) async {
    final k = _chatKeys[chatId]?[keyId];
    if (k != null) return k;
    // (a block body: returning the removed Future here would make it wait on itself)
    await (_keyLoads[chatId] ??= _loadMyChatKeys(chatId).whenComplete(() {
      _keyLoads.remove(chatId);
    }));
    return _chatKeys[chatId]?[keyId];
  }

  /// The key new messages in this chat are sealed with. Makes a new chat key
  /// when there is none, when I have no copy, or when someone left; hands
  /// copies to members who have none yet. Needs the network.
  Future<({int id, SecretKey key})> _sendKey(String chatId, {int depth = 0}) async {
    final cached = _sendKeys[chatId];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(minutes: 2)) return (id: cached.id, key: cached.key);
    final st = Map<String, dynamic>.from(await _sb.rpc('chat_key_state', params: {'c': chatId}).timeout(_net) as Map);
    final latest = (st['latest'] as num?)?.toInt();
    bool ok(Map m) => _mayHold(chatId, m['user_id'] as String) && _trusted(m['user_id'] as String, m['public_key'] as String);
    final keys = (st['keys'] as List).cast<Map>().where(ok).toList();
    final missing = (st['missing'] as List).cast<Map>().where(ok).toList();
    var key = latest == null ? null : await _keyFor(chatId, latest);
    if (latest == null || key == null || st['stale'] == true || missing.any((m) => m['user_id'] == myId)) {
      final id = (latest ?? 0) + 1;
      final k = await E2E.instance.newChatKey();
      final rows = [
        for (final m in keys)
          {
            'chat_id': chatId,
            'user_id': m['user_id'],
            'key_id': id,
            'wrapped': await E2E.instance.wrap(k, chatId: chatId, keyId: id, recipientId: m['user_id'] as String, recipientPub: m['public_key'] as String),
            'wrapped_by': myId,
            'for_pub': m['public_key'],
          },
      ];
      try {
        await _sb.from('chat_keys').insert(rows).timeout(_net);
      } on PostgrestException catch (e) {
        // someone else made this key number at the same moment: use theirs
        if (e.code == '23505' && depth < 3) return await _sendKey(chatId, depth: depth + 1);
        rethrow;
      }
      _rememberKey(chatId, id, k);
      _sendKeys[chatId] = (id: id, key: k, at: DateTime.now());
      return (id: id, key: k);
    }
    if (missing.isNotEmpty) {
      final rows = [
        for (final m in missing)
          {
            'chat_id': chatId,
            'user_id': m['user_id'],
            'key_id': latest,
            'wrapped': await E2E.instance.wrap(
              key,
              chatId: chatId,
              keyId: latest,
              recipientId: m['user_id'] as String,
              recipientPub: m['public_key'] as String,
            ),
            'wrapped_by': myId,
            'for_pub': m['public_key'],
          },
      ];
      try {
        await _sb.rpc('put_chat_keys', params: {'rows': rows}).timeout(_net);
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        // a server before v10: new copies only (old ones cannot be replaced there)
        await _sb.from('chat_keys').upsert(rows, ignoreDuplicates: true).timeout(_net);
      }
    }
    _sendKeys[chatId] = (id: latest, key: key, at: DateTime.now());
    return (id: latest, key: key);
  }

  bool _resealing = false;

  /// My messages from before encryption: sealed now, and their plain files
  /// replaced by encrypted copies and deleted, so nothing old stays readable
  /// on the server. Runs in the background, a batch per start.
  Future<void> _resealOld() async {
    if (!E2E.instance.ready || !_v9 || _resealing || myId == null) return;
    _resealing = true;
    final touched = <String>{};
    try {
      for (var round = 0; round < 20; round++) {
        final rows = await _sb.from('messages').select().eq('sender_id', myId!).isFilter('cipher', null).isFilter('deleted_at', null).limit(50).timeout(_net);
        if (rows.isEmpty) break;
        var done = 0;
        for (final r in rows) {
          final chatId = r['chat_id'] as String;
          final id = r['id'] as String;
          if (_plain(chatId) || chatById(chatId) == null) continue; // channel posts stay public
          try {
            final sk = await _sendKey(chatId);
            var meta = r['meta'] == null ? null : Map<String, dynamic>.from(r['meta'] as Map);
            String? newPath;
            final old = <String>[];
            final fp = r['file_path'] as String?;
            if (fp != null) {
              final enc = await _resealFile(fp);
              if (enc == null) continue;
              newPath = enc.path;
              old.add(fp);
              meta = {...?meta, 'fk': enc.key};
            }
            if (meta?['items'] is List) {
              final items = <Map<String, dynamic>>[];
              for (final it in (meta!['items'] as List).cast<Map>()) {
                final ip = it['path'] as String?;
                final enc = ip == null ? null : await _resealFile(ip);
                if (enc == null) throw StateError('file');
                old.add(ip!);
                items.add({...Map<String, dynamic>.from(it), 'path': enc.path, 'k': enc.key});
              }
              meta['items'] = items;
            }
            final body = (r['body'] as String?) ?? '';
            final payload = <String, dynamic>{'b': body, 'm': meta, 'fn': r['file_name'], 'mt': r['mime_type'], 'd': r['duration_ms']}
              ..removeWhere((_, v) => v == null);
            final cipher = await E2E.instance.seal(sk.key, payload, chatId: chatId, msgId: id, senderId: myId!, keyId: sk.id);
            await _sb.rpc('seal_old_message', params: {'m': id, 'new_cipher': cipher, 'new_key_id': sk.id, 'new_file_path': newPath}).timeout(_net);
            if (old.isNotEmpty) {
              try {
                await _sb.storage.from(AppConfig.attachmentsBucket).remove(old).timeout(_net);
              } catch (_) {}
            }
            touched.add(chatId);
            done++;
          } catch (_) {}
        }
        if (done == 0) break; // nothing more we can do now
      }
    } catch (_) {
    } finally {
      _resealing = false;
    }
    for (final c in touched) {
      if (_messages[c] != null) unawaited(loadMessages(c));
    }
  }

  /// A plain file → an encrypted copy beside it (same chat folder).
  Future<({String path, String key})?> _resealFile(String path) async {
    final raw = await MediaCache.instance.bytes(path, () => fileUrl(path));
    if (raw == null) return null;
    final key = E2E.newFileKey();
    final sealed = await E2E.sealFile(raw, key);
    final parts = path.split('/');
    final np = '${parts.first}/${DateTime.now().microsecondsSinceEpoch}-e-${parts.last}';
    await _sb.storage
        .from(AppConfig.attachmentsBucket)
        .uploadBinary(np, sealed, fileOptions: const FileOptions(contentType: 'application/octet-stream'))
        .timeout(const Duration(seconds: 60));
    await MediaCache.instance.store.save(np, raw);
    registerFileKey(np, key);
    return (path: np, key: key);
  }

  /// A channel: its posts are public announcements, never sealed.
  bool _plain(String chatId) => chatById(chatId)?.isChannel ?? false;

  /// Opening a chat: give the key to members who joined or set up keys since.
  void _shareKeysSoon(String chatId) {
    if (!E2E.instance.ready || _plain(chatId)) return;
    _sendKeys.remove(chatId);
    unawaited(_sendKey(chatId).then((_) {}, onError: (_) {}));
  }

  /// A server row → the same row with the sealed content opened.
  Future<Map<String, dynamic>> _open(Map<String, dynamic> row) async {
    final c = row['cipher'] as String?;
    final keyId = (row['key_id'] as num?)?.toInt();
    if (c == null || keyId == null) return row;
    final out = Map<String, dynamic>.from(row)..remove('cipher');
    final chatId = row['chat_id'] as String;
    final key = E2E.instance.ready ? await _keyFor(chatId, keyId) : null;
    final p = key == null
        ? null
        : await E2E.instance.open(key, c, chatId: chatId, msgId: row['id'] as String, senderId: row['sender_id'] as String, keyId: keyId);
    if (p == null) return out..['locked'] = true;
    out['body'] = p['b'] ?? '';
    if (p['m'] != null) out['meta'] = p['m'];
    if (p['fn'] != null) out['file_name'] = p['fn'];
    if (p['mt'] != null) out['mime_type'] = p['mt'];
    if (p['d'] != null) out['duration_ms'] = p['d'];
    return out;
  }

  /// The key of an encrypted file, from the message it belongs to.
  String? _fileKeyOf(String path) {
    final chatId = path.split('/').first;
    for (final m in _messages[chatId] ?? const <Message>[]) {
      if (m.filePath == path) return m.fileKey;
      for (final it in m.albumItems) {
        if (it['path'] == path) return it['k'] as String?;
      }
    }
    final last = chatById(chatId)?.lastMessage;
    if (last?.filePath == path) return last!.fileKey;
    return null;
  }

  Future<Uint8List?> _openDownloaded(String key, Uint8List raw) async {
    final fk = _fileKeys[key] ?? (key.startsWith('stories/') || key.startsWith('avatars/') ? null : _fileKeyOf(key));
    return fk == null ? raw : E2E.openFile(raw, fk);
  }

  /// Safety number with [other] (compare on both phones), or null.
  Future<String?> safetyNumber(String other) async {
    final mine = E2E.instance.publicKey;
    if (mine == null) return null;
    try {
      _pubs.remove(other);
      final theirs = await _pubOf(other);
      return theirs == null ? null : await E2E.safetyNumber(mine, theirs);
    } catch (_) {
      return null;
    }
  }

  /// A chat whose newest message is still waiting to be sent shows it (with a clock).
  void _showOutboxInChats() {
    for (final it in _outbox) {
      final chat = chatById(it['chat'] as String);
      final m = messageById(it['chat'] as String, it['id'] as String);
      if (chat == null || m == null) continue;
      if (!m.createdAt.isBefore(chat.lastMessageAt)) {
        chat.lastMessage = m;
        chat.lastMessageAt = m.createdAt;
      }
    }
    _sortChats();
  }

  void _onSignedOut() {
    _channel?.unsubscribe();
    _channel = null;
    _typingCh?.unsubscribe();
    _typingCh = null;
    me = null;
    chats = [];
    chatsLoaded = false;
    _messages.clear();
    _signedUrls.clear();
    _outbox.clear();
    _failedItems.clear();
    _diskLoaded.clear();
    _retryTimer?.cancel();
    openChatId = null;
    realtimeOnline = false;
  }

  Future<void> _loadProfile() async {
    try {
      final row = await _sb.from('profiles').select().eq('id', myId!).single().timeout(_net);
      me = Profile.fromJson(row);
      unawaited(MediaCache.instance.store.writeJson('${_cachePrefix}_me', row));
      notifyListeners();
    } catch (_) {}
  }

  // ── Typing ("typing…"), like Telegram / WhatsApp ───────────────────────
  // Each person listens on their own private channel; whoever types in a
  // chat tells the other members there (the server lets only people who
  // share a chat send to it — v12). Nothing is stored anywhere.
  RealtimeChannel? _typingCh;
  final Map<String, RealtimeChannel> _typingOut = {};
  final Map<String, DateTime> _typedAt = {}; // chat → when I last told them

  /// chat id → (person → until when they count as typing)
  final Map<String, Map<String, DateTime>> typing = {};
  Timer? _typingTick;

  void _subscribeTyping() {
    _typingCh?.unsubscribe();
    _typingCh = _sb.channel('typing:${myId!}', opts: const RealtimeChannelConfig(private: true)).onBroadcast(event: 't', callback: _onTyping).subscribe();
  }

  void _onTyping(Map<String, dynamic> p) {
    final data = p['payload'] is Map ? Map<String, dynamic>.from(p['payload'] as Map) : p;
    final c = data['c'], u = data['u'];
    if (c is! String || u is! String || u == myId || chatById(c) == null) return;
    typing.putIfAbsent(c, () => {})[u] = DateTime.now().add(const Duration(seconds: 6));
    _typingTick ??= Timer.periodic(const Duration(seconds: 1), (_) => _expireTyping());
    notifyListeners();
  }

  void _expireTyping() {
    final now = DateTime.now();
    var changed = false;
    for (final m in typing.values) {
      final n = m.length;
      m.removeWhere((_, until) => until.isBefore(now));
      changed |= m.length != n;
    }
    typing.removeWhere((_, m) => m.isEmpty);
    if (typing.isEmpty) {
      _typingTick?.cancel();
      _typingTick = null;
    }
    if (changed) notifyListeners();
  }

  /// Who is typing in [chat] right now (not me).
  List<Profile> typingIn(Chat chat) => [
    for (final id in typing[chat.id]?.keys ?? const <String>[])
      if (memberById(chat, id) case final p?) p,
  ];

  /// "typing…" / "Ahmad is typing…" / null.
  String? typingText(Chat chat) {
    final who = typingIn(chat);
    if (who.isEmpty) return null;
    if (!chat.isGroup) return s.get('typing');
    return s.get('typing_name', {'name': who.first.name});
  }

  /// The composer changed: tell the others, at most every 4 seconds.
  void userTyping(Chat chat) {
    if (myId == null || chat.isSaved || chat.isChannel) return;
    final last = _typedAt[chat.id];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 3)) return;
    _typedAt[chat.id] = DateTime.now();
    final others = chat.members.where((m) => m.id != myId).take(30);
    for (final m in others) {
      final ch = _typingOut[m.id] ??= _sb.channel('typing:${m.id}', opts: const RealtimeChannelConfig(private: true));
      unawaited(ch.httpSend(event: 't', payload: {'c': chat.id, 'u': myId}).catchError((_) {}));
    }
  }

  void _stopTypingOf(String chatId, String userId) {
    if (typing[chatId]?.remove(userId) != null) {
      typing.removeWhere((_, m) => m.isEmpty);
      notifyListeners();
    }
  }

  // ── Realtime ─────────────────────────────────────────────────────────────
  void _subscribe() {
    _subscribeTyping();
    _channel?.unsubscribe();
    _channel = _sb
        .channel('paigham-${myId!}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) async => _onMessage(Message.fromJson(await _open(p.newRecord))),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (p) async => _onMessageUpdate(Message.fromJson(await _open(p.newRecord))),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (p) => _onReaction(p.eventType, p.newRecord, p.oldRecord),
        )
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'stories', callback: (_) => loadStories())
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'chats', callback: (_) => _scheduleReload())
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_members',
          callback: (p) {
            _sendKeys.clear();
            _onMemberUpdate(p.newRecord);
          },
        )
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'chat_members', callback: (_) => _scheduleReload())
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'profiles',
          callback: (_) => _scheduleReload(), // name or photo changed
        )
        .subscribe((status, [err]) {
          final online = status == RealtimeSubscribeStatus.subscribed;
          if (online && !realtimeOnline) _scheduleReload(); // catch up after a reconnect
          realtimeOnline = online;
          notifyListeners();
        });
  }

  void _onMessage(Message m, {bool notify = true}) {
    _stopTypingOf(m.chatId, m.senderId); // their message arrived: no longer typing
    _persistSoon(m.chatId);
    final list = _messages[m.chatId];
    if (list != null) {
      // ids are made on the phone, so our own pending copy has the same id
      final i = list.indexWhere((x) => x.id == m.id);
      if (i < 0) {
        list.add(m); // also our messages sent from another device
      } else if (list[i].pending) {
        list[i] = m;
      }
    }
    final chat = chatById(m.chatId);
    if (chat == null) {
      _scheduleReload();
      return;
    }
    chat.lastMessage = m;
    chat.lastMessageAt = m.createdAt;
    if (m.senderId != myId) {
      if (openChatId == m.chatId) {
        markRead(chat);
      } else {
        chat.unread++;
      }
      // Like Telegram: a new message brings an archived chat back unless it is muted.
      if (chat.archived && !chat.muted) unawaited(setArchived(chat, false));
      if (!chat.muted && notify) {
        _incoming.add(m);
        _notify(chat, m);
      }
    }
    _sortChats();
    notifyListeners();
  }

  /// A system notification for a new message, unless that chat is open on
  /// screen right now (also while the app is in front, like Telegram).
  void _notify(Chat chat, Message m) {
    if (foreground && openChatId == chat.id) return;
    final sender = memberById(chat, m.senderId)?.name ?? '';
    Notifier.instance.show(
      id: chat.id.hashCode & 0x7fffffff,
      title: chat.isGroup ? '${chatTitle(chat)} · $sender' : sender,
      body: previewOf(m),
      payload: 'chat:${chat.id}',
    );
  }

  void _onMessageUpdate(Message m) {
    _persistSoon(m.chatId);
    final list = _messages[m.chatId];
    if (list != null) {
      final i = list.indexWhere((x) => x.id == m.id);
      if (i >= 0) list[i] = m;
    }
    final chat = chatById(m.chatId);
    if (chat != null && chat.lastMessage?.id == m.id) chat.lastMessage = m;
    notifyListeners();
  }

  Message? messageById(String chatId, String id) {
    for (final m in _messages[chatId] ?? const <Message>[]) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// "Delete for everyone": the server blanks the message; others see a placeholder.
  // ── Delete for me (Telegram): hidden on this phone only ─────────────────
  Set<String>? _hidden;
  Set<String> get hiddenIds => _hidden ??= {...(_prefs.getStringList('hidden_${myId ?? ''}') ?? const <String>[])};
  bool isHidden(String id) => hiddenIds.contains(id);

  void deleteForMe(Chat chat, Iterable<Message> msgs) {
    hiddenIds.addAll(msgs.map((m) => m.id));
    final list = hiddenIds.toList();
    unawaited(_prefs.setStringList('hidden_${myId ?? ''}', list.length > 5000 ? list.sublist(list.length - 5000) : list));
    notifyListeners();
  }

  /// May I delete [m] for everyone? My own messages; in groups also admins
  /// with the delete right.
  bool canDeleteForAll(Chat chat, Message m) => m.senderId == myId || (chat.isGroup && chat.can(myId ?? '', 'delete'));

  Future<void> deleteMessage(Chat chat, Message m) async {
    if (m.senderId != myId && !(chat.isGroup && chat.can(myId ?? '', 'delete'))) return;
    try {
      await _sb.rpc('delete_message', params: {'m': m.id});
      final path = m.filePath;
      if (path != null) {
        try {
          await _sb.storage.from(AppConfig.attachmentsBucket).remove([path]);
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _onMemberUpdate(Map<String, dynamic> row) {
    final chat = chatById(row['chat_id'] as String);
    if (chat == null) return;
    if (row['user_id'] == myId) {
      // my own settings changed (maybe on another device)
      if (row.containsKey('muted')) chat.muted = (row['muted'] as bool?) ?? false;
      if (row.containsKey('archived')) chat.archived = (row['archived'] as bool?) ?? false;
      if (row.containsKey('marked_unread')) chat.markedUnread = (row['marked_unread'] as bool?) ?? false;
      if (row.containsKey('pinned_at')) chat.pinnedAt = row['pinned_at'] == null ? null : DateTime.parse(row['pinned_at'] as String).toLocal();
      _sortChats();
    }
    if (row['last_read_at'] == null) {
      notifyListeners();
      return;
    }
    final at = DateTime.parse(row['last_read_at'] as String).toLocal();
    chat.members = [
      for (final m in chat.members)
        m.id == row['user_id']
            ? Profile(
                id: m.id,
                email: m.email,
                displayName: m.displayName,
                username: m.username,
                avatarPath: m.avatarPath,
                lastReadAt: at,
                role: m.role,
                rights: m.rights,
                lastSeen: m.lastSeen,
                verified: m.verified,
              )
            : m,
    ];
    notifyListeners();
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 300), () {
      reloadChats();
      unawaited(_drain()); // back online / back in the app: send what waits
    });
  }

  /// Network calls give up after this, so a dead connection never blocks the screen.
  static const _net = Duration(seconds: 20);

  // ── Chats ────────────────────────────────────────────────────────────────
  Future<void> reloadChats() async {
    if (myId == null) return;
    try {
      final data = await _sb.rpc('my_chats').timeout(_net) as List<dynamic>;
      if (E2E.instance.ready && data.any((e) => (e as Map)['last_message'] is Map && e['last_message']['cipher'] != null)) {
        await _loadMyChatKeys(); // one query for all chats
        // all chats at once, not one after another (faster on opening)
        await Future.wait([
          for (final e in data.cast<Map<String, dynamic>>())
            if (e['last_message'] is Map && e['last_message']['cipher'] != null)
              _open(Map<String, dynamic>.from(e['last_message'] as Map)).then((v) => e['last_message'] = v),
        ]);
      }
      final before = {for (final c in chats) c.id: c.lastMessage?.id};
      final hadChats = chats.isNotEmpty;
      chats = data.map((e) => Chat.fromJson(e as Map<String, dynamic>)).toList();
      unawaited(MediaCache.instance.store.writeJson('${_cachePrefix}_chats', data));
      // Catch up on what the live connection missed (it is often cut while the
      // app is in the background): fill open/loaded chats and notify.
      for (final c in chats) {
        final last = c.lastMessage;
        if (last == null || before[c.id] == last.id) continue;
        final list = _messages[c.id];
        if (list != null && !list.any((x) => x.id == last.id)) unawaited(loadMessages(c.id));
        // only while the app is away: in front the list itself shows it, and
        // a push already announced it (no second notification on opening)
        if (!foreground && hadChats && last.senderId != myId && !c.muted && before.containsKey(c.id)) _notify(c, last);
      }
      _showOutboxInChats();
      final open = openChatId == null ? null : chatById(openChatId!);
      if (open != null) open.unread = 0;
      _sortChats();
    } catch (_) {}
    chatsLoaded = true;
    notifyListeners();
  }

  /// Pinned chats first (last pinned on top), then newest activity.
  void _sortChats() => chats.sort((a, b) {
    final pa = a.pinnedAt, pb = b.pinnedAt;
    if (pa != null || pb != null) {
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pb.compareTo(pa);
    }
    return b.lastMessageAt.compareTo(a.lastMessageAt);
  });

  Chat? chatById(String id) {
    for (final c in chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Badge on the Chats tab: muted and archived chats don't count.
  int get totalUnread => chats.fold(0, (n, c) => c.muted || c.archived ? n : n + (c.unread > 0 ? c.unread : (c.markedUnread ? 1 : 0)));

  /// Blue tick: an official channel, or a chat with a verified person.
  bool isVerified(Chat c) => c.verified || (!c.isGroup && !c.isSaved && (c.peer(myId ?? '')?.verified ?? false));

  String chatTitle(Chat c) => c.isSaved ? s.get('saved_messages') : c.displayTitle(myId ?? '');

  // ── Chat options (each person's own view) ────────────────────────────────
  Future<bool> _setMine(Chat chat, Map<String, dynamic> fields) async {
    if (myId == null) return false;
    try {
      await _sb.from('chat_members').update(fields).eq('chat_id', chat.id).eq('user_id', myId!);
      return true;
    } catch (_) {
      return false;
    }
  }

  static const maxPinned = 5;

  /// Returns false when the pin limit is reached.
  Future<bool> togglePinChat(Chat chat) async {
    if (chat.pinnedAt == null && chats.where((c) => c.pinnedAt != null && c.archived == chat.archived).length >= maxPinned) return false;
    chat.pinnedAt = chat.pinnedAt == null ? DateTime.now() : null;
    _sortChats();
    notifyListeners();
    await _setMine(chat, {'pinned_at': chat.pinnedAt?.toUtc().toIso8601String()});
    return true;
  }

  Future<void> toggleMute(Chat chat) async {
    chat.muted = !chat.muted;
    notifyListeners();
    await _setMine(chat, {'muted': chat.muted});
  }

  Future<void> setArchived(Chat chat, bool archived) async {
    chat.archived = archived;
    if (archived) chat.pinnedAt = null;
    _sortChats();
    notifyListeners();
    await _setMine(chat, {'archived': archived, if (archived) 'pinned_at': null});
  }

  /// Mark as read when there is something unread, otherwise mark as unread.
  Future<void> toggleUnread(Chat chat) async {
    if (chat.unread > 0 || chat.markedUnread) {
      chat.markedUnread = false;
      await markRead(chat);
      await _setMine(chat, {'marked_unread': false});
    } else {
      chat.markedUnread = true;
      notifyListeners();
      await _setMine(chat, {'marked_unread': true});
    }
  }

  /// Hides every message up to now, for me only.
  Future<void> clearHistory(Chat chat) async {
    final list = _messages[chat.id] ?? const <Message>[];
    DateTime? newest = chat.lastMessage?.createdAt;
    for (final m in list) {
      if (!m.pending && (newest == null || m.createdAt.isAfter(newest))) newest = m.createdAt;
    }
    if (newest == null) return;
    chat.clearedAt = newest;
    _messages[chat.id] = [
      for (final m in list)
        if (m.createdAt.isAfter(newest)) m,
    ];
    chat.lastMessage = null;
    chat.unread = 0;
    chat.markedUnread = false;
    notifyListeners();
    await _setMine(chat, {'cleared_at': newest.toUtc().toIso8601String(), 'marked_unread': false});
  }

  /// My "Saved Messages" chat (created on first use).
  Future<Chat?> savedChat() async {
    for (final c in chats) {
      if (c.isSaved) return c;
    }
    try {
      final id = await _sb.rpc('saved_chat') as String;
      await reloadChats();
      return chatById(id);
    } catch (_) {
      return null;
    }
  }

  Profile? memberById(Chat c, String id) {
    for (final m in c.members) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Exact match on email or @username.
  Future<Profile?> findUser(String query) async {
    final rows = await _sb.rpc('find_user', params: {'q': query.trim()}) as List<dynamic>;
    return rows.isEmpty ? null : Profile.fromJson(rows.first as Map<String, dynamic>);
  }

  Future<Chat?> startDirectChat(Profile other) async {
    final id = await _sb.rpc('start_direct_chat', params: {'other': other.id}) as String;
    await reloadChats();
    return chatById(id);
  }

  /// Opens (or creates) the one-to-one chat with a user id.
  Future<Chat?> openDirect(String userId) async {
    try {
      final id = await _sb.rpc('start_direct_chat', params: {'other': userId}) as String;
      await reloadChats();
      return chatById(id);
    } catch (_) {
      return null;
    }
  }

  Future<Chat?> createGroup(String title, List<Profile> members) async {
    final id = await _sb.rpc('create_group', params: {'title': title.trim(), 'members': members.map((m) => m.id).toList()}) as String;
    await reloadChats();
    return chatById(id);
  }

  Future<void> addMember(Chat chat, Profile p) async {
    await _sb.rpc('add_group_member', params: {'chat': chat.id, 'member': p.id});
    await reloadChats();
  }

  Future<void> leaveChat(Chat chat) async {
    await _sb.from('chat_members').delete().eq('chat_id', chat.id).eq('user_id', myId!);
    chats.remove(chat);
    _messages.remove(chat.id);
    notifyListeners();
  }

  // ── Group management (Telegram-like) ────────────────────────────────────
  /// Runs a group action; returns null or a translation key for the error.
  Future<String?> _groupCall(String fn, Map<String, dynamic> params) async {
    try {
      await _sb.rpc(fn, params: params).timeout(_net);
      await reloadChats();
      return null;
    } on PostgrestException catch (e) {
      if (e.message.contains('banned')) return 'user_banned';
      if (e.message.contains('not allowed')) return 'not_allowed';
      if (e.code == '23505') return 'username_taken';
      return 'err_generic';
    } catch (_) {
      return 'err_network';
    }
  }

  Future<String?> updateGroup(Chat chat, {String? title, String? description}) =>
      _groupCall('update_group', {'c': chat.id, 'new_title': title, 'new_description': description});

  Future<String?> setGroupPermissions(Chat chat, Map<String, bool> perms) => _groupCall('set_group_permissions', {'c': chat.id, 'perms': perms});

  Future<String?> setMemberRole(Chat chat, String userId, {required bool admin, Map<String, bool>? rights}) =>
      _groupCall('set_member_role', {'c': chat.id, 'u': userId, 'new_role': admin ? 'admin' : 'member', 'new_rights': rights});

  Future<String?> removeMember(Chat chat, String userId, {bool ban = false}) async {
    final err = await _groupCall('remove_member', {'c': chat.id, 'u': userId, 'ban': ban});
    _sendKeys.remove(chat.id); // the next message gets a new chat key
    return err;
  }

  Future<String?> unbanMember(Chat chat, String userId) => _groupCall('unban_member', {'c': chat.id, 'u': userId});

  Future<String?> setGroupUsername(Chat chat, String username) => _groupCall('set_group_username', {'c': chat.id, 'uname': username});

  Future<String?> deleteGroup(Chat chat) async {
    final err = await _groupCall('delete_group', {'c': chat.id});
    if (err == null) {
      chats.remove(chat);
      _messages.remove(chat.id);
      notifyListeners();
    }
    return err;
  }

  /// People banned from a group.
  Future<List<Profile>> bannedOf(Chat chat) async {
    try {
      final rows = await _sb.from('chat_bans').select('user_id').eq('chat_id', chat.id).timeout(_net);
      final ids = [for (final r in rows) r['user_id'] as String];
      if (ids.isEmpty) return [];
      final ps = await _sb.from('profiles').select('id,email,display_name,username,avatar_path').inFilter('id', ids).timeout(_net);
      return [for (final p in ps) Profile.fromJson(p)];
    } catch (_) {
      return [];
    }
  }

  // invite links: paigham://join/<code>
  Future<String?> createInvite(Chat chat, {int? hours, int? maxUses}) async {
    try {
      final code = await _sb.rpc('create_invite', params: {'c': chat.id, 'hours': hours, 'max_uses': maxUses}).timeout(_net) as String;
      return 'paigham://join/$code';
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> invitesOf(Chat chat) async {
    try {
      final rows = await _sb.from('chat_invites').select().eq('chat_id', chat.id).eq('revoked', false).order('created_at', ascending: false).timeout(_net);
      return [for (final r in rows) Map<String, dynamic>.from(r)];
    } catch (_) {
      return [];
    }
  }

  Future<void> revokeInvite(String code) async {
    try {
      await _sb.rpc('revoke_invite', params: {'k': code}).timeout(_net);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> inviteInfo(String code) async {
    try {
      final r = await _sb.rpc('invite_info', params: {'k': code}).timeout(_net);
      return r == null ? null : Map<String, dynamic>.from(r as Map);
    } catch (_) {
      return null;
    }
  }

  Future<Chat?> joinByInvite(String code) async {
    try {
      final id = await _sb.rpc('join_by_invite', params: {'k': code}).timeout(_net) as String;
      await reloadChats();
      return chatById(id);
    } catch (_) {
      return null;
    }
  }

  // ── Messages ─────────────────────────────────────────────────────────────
  List<Message>? messagesOf(String chatId) => _messages[chatId];
  final Set<String> _diskLoaded = {};

  /// The chat's messages saved on the phone (once per run): instant, offline.
  Future<void> _loadDisk(String chatId) async {
    final cacheName = '${_cachePrefix}_m_$chatId';
    if (_diskLoaded.add(chatId)) {
      // last seen messages first, from the phone — instant, and works offline
      final cached = await MediaCache.instance.store.readJson(cacheName);
      if (cached is List) {
        try {
          final list = _messages.putIfAbsent(chatId, () => []);
          for (final m in cached.map((e) => Message.fromJson(e as Map<String, dynamic>))) {
            if (!list.any((x) => x.id == m.id)) list.add(m);
          }
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          notifyListeners();
        } catch (_) {}
      }
    }
  }

  /// Search in the messages kept on this phone (they are end-to-end
  /// encrypted, so the server cannot search them — like WhatsApp). [kind]
  /// narrows to photos ('media'), files, voice notes or links.
  Future<List<({Chat chat, Message m})>> searchMessages(String query, {String? chatId, String? kind}) async {
    final q = query.trim().toLowerCase();
    final chatsToSearch = chatId == null ? List.of(chats) : [?chatById(chatId)];
    for (final c in chatsToSearch) {
      await _loadDisk(c.id);
    }
    final link = RegExp(r'https?://|paigham://|www\.', caseSensitive: false);
    final out = <({Chat chat, Message m})>[];
    for (final c in chatsToSearch) {
      for (final m in _messages[c.id] ?? const <Message>[]) {
        if (m.deleted || m.locked || isHidden(m.id)) continue;
        final ok = switch (kind) {
          'media' => m.kind == MsgKind.image || m.kind == MsgKind.album,
          'files' => m.kind == MsgKind.file,
          'voice' => m.kind == MsgKind.voice,
          'links' => link.hasMatch(m.body),
          _ => true,
        };
        if (!ok) continue;
        if (q.isNotEmpty && !RichMessageText.strip(m.body).toLowerCase().contains(q) && !(m.fileName ?? '').toLowerCase().contains(q)) continue;
        if (q.isEmpty && kind == null) continue;
        out.add((chat: c, m: m));
      }
    }
    out.sort((a, b) => b.m.createdAt.compareTo(a.m.createdAt));
    return out.length > 300 ? out.sublist(0, 300) : out;
  }

  /// Messages pushes brought while the app was away (already opened on the
  /// phone): into the chat list and the chat before anything is fetched.
  Future<void> _drainInbox() async {
    List<Map<String, dynamic>> rows;
    try {
      rows = await PushInbox.take();
    } catch (_) {
      return;
    }
    for (final r in rows) {
      try {
        final m = Message.fromJson(r);
        if (chatById(m.chatId) == null) continue;
        await _loadDisk(m.chatId);
        _messages.putIfAbsent(m.chatId, () => []);
        final known = _messages[m.chatId]!.any((x) => x.id == m.id);
        if (!known) _onMessage(m, notify: false);
      } catch (_) {}
    }
  }

  Future<void> loadMessages(String chatId) async {
    unawaited(_loadReactions(chatId));
    await _loadDisk(chatId);
    try {
      final cleared = chatById(chatId)?.clearedAt;
      var q = _sb.from('messages').select().eq('chat_id', chatId);
      if (cleared != null) q = q.gt('created_at', cleared.toUtc().toIso8601String());
      final rows = await q.order('created_at', ascending: false).limit(300).timeout(_net);
      final opened = await Future.wait(rows.map(_open));
      final list = opened.map(Message.fromJson).toList().reversed.toList();
      for (final m in _messages[chatId] ?? const <Message>[]) {
        if (!list.any((x) => x.id == m.id)) list.add(m); // keep pending/realtime ones
      }
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _messages[chatId] = list;
      _persistSoon(chatId);
    } catch (_) {
      _messages.putIfAbsent(chatId, () => []);
    }
    notifyListeners();
  }

  void openChat(String id) {
    openChatId = id;
    _shareKeysSoon(id);
    // always ask the server too: messages that came while the live
    // connection was down (app in the background) would otherwise be missing
    loadMessages(id);
    final c = chatById(id);
    if (c != null) markRead(c);
  }

  void closeChat(String id) {
    if (openChatId == id) openChatId = null;
  }

  Future<void> markRead(Chat chat) async {
    final last = chat.lastMessage;
    if (chat.markedUnread) {
      chat.markedUnread = false;
      unawaited(_setMine(chat, {'marked_unread': false}));
    }
    if (chat.unread > 0) {
      chat.unread = 0;
      notifyListeners();
    }
    if (last == null || myId == null) return;
    // Server timestamp of the newest message, so device clock errors don't matter.
    final at = last.createdAt.toUtc().toIso8601String();
    try {
      await _sb.from('chat_members').update({'last_read_at': at}).eq('chat_id', chat.id).eq('user_id', myId!).lt('last_read_at', at);
    } catch (_) {}
  }

  /// One tick = sent; two ticks = read (direct: by the other person, group: by anyone).
  MsgStatus statusOf(Chat chat, Message m) {
    if (m.failed) return MsgStatus.failed;
    if (m.pending) return MsgStatus.sending;
    final others = chat.members.where((p) => p.id != myId).toList();
    final readers = others.where((p) => p.lastReadAt != null && !p.lastReadAt!.isBefore(m.createdAt));
    if (others.isNotEmpty && (chat.isGroup ? readers.isNotEmpty : readers.length == others.length)) {
      return MsgStatus.read;
    }
    return MsgStatus.sent;
  }

  // ── Sending: a queue kept on the phone (works offline) ──────────────────
  // Every outgoing message goes into the outbox first and shows at once with
  // a clock. The outbox is saved to disk and sent in order; with no internet
  // it waits and retries by itself (also after the app restarts). Each
  // message has its final id from the start, so a retry never duplicates it.
  final List<Map<String, dynamic>> _outbox = [];
  final Map<String, Map<String, dynamic>> _failedItems = {};
  bool _draining = false;
  Timer? _retryTimer;

  static String _uuid() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Message _local(
    Chat chat,
    MsgKind kind,
    String body, {
    String? name,
    int? size,
    String? mime,
    Uint8List? bytes,
    String? replyTo,
    int? durationMs,
    Map<String, dynamic>? meta,
    String? filePath,
    List<Uint8List>? album,
    String? id,
  }) {
    final m = Message(
      id: id ?? _uuid(),
      chatId: chat.id,
      senderId: myId!,
      kind: kind,
      body: body,
      createdAt: DateTime.now(),
      filePath: filePath,
      fileName: name,
      fileSize: size,
      mimeType: mime,
      replyTo: replyTo,
      durationMs: durationMs,
      localBytes: bytes,
      localAlbum: album,
      meta: meta,
      pending: true,
    );
    _messages.putIfAbsent(chat.id, () => []).add(m);
    chat.lastMessage = m;
    chat.lastMessageAt = m.createdAt;
    _sortChats();
    notifyListeners();
    return m;
  }

  void _replace(Chat chat, Message local, Message saved) {
    _persistSoon(chat.id);
    final list = _messages.putIfAbsent(chat.id, () => []);
    final i = list.indexWhere((x) => x.id == local.id || identical(x, local));
    list.removeWhere((x) => x.id == saved.id && !identical(x, local));
    final j = list.indexWhere((x) => identical(x, local));
    if (j >= 0) {
      list[j] = saved;
    } else if (i < 0) {
      list.add(saved);
    }
    if (chat.lastMessage == null || chat.lastMessage!.id == saved.id || !saved.createdAt.isBefore(chat.lastMessageAt)) {
      chat.lastMessage = saved;
      chat.lastMessageAt = saved.createdAt;
    }
    _sortChats();
    notifyListeners();
  }

  /// Puts a message in the outbox (with its files saved on the phone first).
  Future<void> _enqueue(
    Chat chat,
    Message local,
    Map<String, dynamic> fields, {
    List<({String path, Uint8List bytes, String mime})> uploads = const [],
    List<({String from, String to})> copies = const [],
  }) async {
    for (final u in uploads) {
      // kept under its server path: shows offline now, and is already cached after sending
      await MediaCache.instance.store.save(u.path, u.bytes);
    }
    // end-to-end: every file gets its own key, carried inside the sealed message
    final fileKeys = <String, String>{};
    if (E2E.instance.ready && uploads.isNotEmpty) {
      for (final u in uploads) {
        fileKeys[u.path] = E2E.newFileKey();
      }
      final meta = Map<String, dynamic>.from((fields['meta'] as Map?) ?? const {});
      if (meta['items'] is List) {
        meta['items'] = [
          for (final it in (meta['items'] as List).cast<Map>()) {...it, 'k': ?fileKeys[it['path']]},
        ];
      } else {
        meta['fk'] = fileKeys[uploads.first.path];
      }
      fields['meta'] = meta;
    }
    for (final c in copies) {
      final b = await MediaCache.instance.store.read(c.from);
      if (b != null) await MediaCache.instance.store.save(c.to, b);
    }
    final item = <String, dynamic>{
      'id': local.id,
      'chat': chat.id,
      'kind': local.kind.name,
      'fields': fields,
      'uploads': [
        for (final u in uploads) {'path': u.path, 'mime': u.mime, 'done': false, 'fk': ?fileKeys[u.path]},
      ],
      'copies': [
        for (final c in copies) {'from': c.from, 'to': c.to, 'done': false},
      ],
      'local': local.toJson(),
    };
    _outbox.add(item);
    await _saveOutbox();
    unawaited(_drain());
  }

  Future<void> _saveOutbox() => MediaCache.instance.store.writeJson('${_cachePrefix}_outbox', _outbox);

  /// Brings back unsent messages after a restart (they keep their clock).
  Future<void> _loadOutbox() async {
    final saved = await MediaCache.instance.store.readJson('${_cachePrefix}_outbox');
    if (saved is! List) return;
    _outbox
      ..clear()
      ..addAll(saved.cast<Map>().map((e) => Map<String, dynamic>.from(e)));
    for (final it in _outbox) {
      final m = Message.fromJson(Map<String, dynamic>.from(it['local'] as Map))..pending = true;
      final list = _messages.putIfAbsent(m.chatId, () => []);
      if (!list.any((x) => x.id == m.id)) list.add(m);
    }
    if (_outbox.isNotEmpty) notifyListeners();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 6), () => unawaited(_drain()));
  }

  /// Sends the outbox in order. Stops at the first network problem and
  /// tries again a little later.
  Future<void> _drain() async {
    if (_draining || myId == null || _outbox.isEmpty) return;
    _draining = true;
    try {
      while (_outbox.isNotEmpty) {
        final it = _outbox.first;
        final r = await _sendItem(it);
        if (r == null) {
          _scheduleRetry();
          break;
        }
        _outbox.removeAt(0);
        await _saveOutbox();
        if (!r) {
          // a real refusal from the server: show the red mark, tap to retry
          _failedItems[it['id'] as String] = it;
          final m = messageById(it['chat'] as String, it['id'] as String);
          if (m != null) {
            m
              ..pending = false
              ..failed = true;
            notifyListeners();
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// true = sent, false = refused (won't work by retrying), null = no network.
  Future<bool?> _sendItem(Map<String, dynamic> it) async {
    const wait = Duration(seconds: 25);
    // nothing leaves the phone unencrypted: wait until the key is here
    // (only a server without the encryption update gets plain messages)
    if (!E2E.instance.ready && keyState != KeyState.unsupported) return null;
    try {
      for (final c in (it['copies'] as List).cast<Map>()) {
        if (c['done'] == true) continue;
        try {
          await _sb.storage.from(AppConfig.attachmentsBucket).copy(c['from'] as String, c['to'] as String).timeout(wait);
        } on StorageException catch (e) {
          if (e.statusCode != '409' && !e.message.toLowerCase().contains('exist')) rethrow;
        }
        c['done'] = true;
        await _saveOutbox();
      }
      for (final u in (it['uploads'] as List).cast<Map>()) {
        if (u['done'] == true) continue;
        var bytes = await MediaCache.instance.store.read(u['path'] as String);
        if (bytes == null) return false;
        final fk = u['fk'] as String?;
        if (fk != null) bytes = await E2E.sealFile(bytes, fk); // the server only gets ciphertext
        try {
          await _sb.storage
              .from(AppConfig.attachmentsBucket)
              .uploadBinary(u['path'] as String, bytes, fileOptions: FileOptions(contentType: fk != null ? 'application/octet-stream' : u['mime'] as String))
              .timeout(wait);
        } on StorageException catch (e) {
          // already there from an earlier try that lost its answer
          if (e.statusCode != '409' && !e.message.toLowerCase().contains('exist')) rethrow;
        }
        u['done'] = true;
        await _saveOutbox();
      }
      final chatId = it['chat'] as String;
      final fields = Map<String, dynamic>.from(it['fields'] as Map);
      if (E2E.instance.ready && !_plain(chatId)) {
        // seal the content: the server keeps only the kind, time and sizes
        final sk = await _sendKey(chatId);
        final payload = <String, dynamic>{
          'b': fields.remove('body') ?? '',
          'm': fields.remove('meta'),
          'fn': fields.remove('file_name'),
          'mt': fields.remove('mime_type'),
          'd': fields.remove('duration_ms'),
        }..removeWhere((_, v) => v == null);
        fields['body'] = '';
        fields['key_id'] = sk.id;
        fields['cipher'] = await E2E.instance.seal(sk.key, payload, chatId: chatId, msgId: it['id'] as String, senderId: myId!, keyId: sk.id);
      }
      Map<String, dynamic> row;
      try {
        row = await _sb
            .from('messages')
            .insert({'id': it['id'], 'chat_id': chatId, 'sender_id': myId, 'kind': it['kind'], ...fields})
            .select()
            .single()
            .timeout(wait);
      } on PostgrestException catch (e) {
        if (e.code != '23505') rethrow; // 23505 = it was saved already
        row = await _sb.from('messages').select().eq('id', it['id'] as String).single().timeout(wait);
      }
      final saved = Message.fromJson(await _open(row));
      final chat = chatById(chatId);
      final local = messageById(chatId, saved.id);
      if (chat != null && local != null) {
        _replace(chat, local, saved);
      } else {
        _persistSoon(chatId);
      }
      return true;
    } on PostgrestException catch (e) {
      final code = e.code ?? '';
      // permission / validation problems are final; anything else: try again later
      return code.startsWith('42') || code.startsWith('23') || code.startsWith('22') ? false : null;
    } on StorageException catch (e) {
      final st = int.tryParse(e.statusCode ?? '') ?? 0;
      return st >= 400 && st < 500 && st != 408 && st != 429 ? false : null;
    } catch (_) {
      return null; // no internet, timeout, …
    }
  }

  /// The X on a message still waiting to be sent: drop it (like Telegram).
  bool cancelSend(Chat chat, Message m) {
    final i = _outbox.indexWhere((it) => it['id'] == m.id);
    final wasFailed = _failedItems.remove(m.id) != null;
    if (i < 0 && !wasFailed) return false;
    if (i == 0 && _draining) return false; // already on its way
    if (i >= 0) {
      _outbox.removeAt(i);
      unawaited(_saveOutbox());
    }
    final list = _messages[chat.id];
    list?.removeWhere((x) => x.id == m.id);
    if (chat.lastMessage?.id == m.id) {
      chat.lastMessage = list == null || list.isEmpty ? null : list.last;
      if (chat.lastMessage != null) chat.lastMessageAt = chat.lastMessage!.createdAt;
    }
    notifyListeners();
    return true;
  }

  /// Unsent and refused counts, for the header.
  int get unsentCount => _outbox.length;

  Future<void> sendText(Chat chat, String text, {String? replyTo, Map<String, dynamic>? meta}) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final local = _local(chat, MsgKind.text, body.length > 4000 ? body.substring(0, 4000) : body, replyTo: replyTo, meta: meta);
    await _enqueue(chat, local, {'body': local.body, 'reply_to': ?replyTo, 'meta': ?meta});
  }

  /// A recorded voice note.
  Future<void> sendVoice(Chat chat, {required Uint8List bytes, required int durationMs, required String ext, String? replyTo}) async {
    if (bytes.isEmpty) return;
    final mime = ext == 'm4a' ? 'audio/mp4' : (ext == 'wav' ? 'audio/wav' : 'audio/webm');
    final name = 'voice-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = '${chat.id}/$name';
    final local = _local(
      chat,
      MsgKind.voice,
      '',
      name: name,
      size: bytes.length,
      mime: mime,
      bytes: bytes,
      replyTo: replyTo,
      durationMs: durationMs,
      filePath: path,
    );
    await _enqueue(
      chat,
      local,
      {'file_path': path, 'file_name': name, 'file_size': bytes.length, 'mime_type': mime, 'duration_ms': durationMs, 'reply_to': ?replyTo},
      uploads: [(path: path, bytes: bytes, mime: mime)],
    );
  }

  /// A photo or file. Returns a translation key for client-side errors.
  Future<String?> sendFile(Chat chat, {required String name, required Uint8List bytes, String caption = '', String? replyTo}) async {
    if (bytes.length > AppConfig.maxFileBytes) return 'too_big';
    final mime = mimeFor(name);
    final kind = mime.startsWith('image/') ? MsgKind.image : MsgKind.file;
    final path = '${chat.id}/${DateTime.now().millisecondsSinceEpoch}-${_safe(name)}';
    final local = _local(chat, kind, caption, name: name, size: bytes.length, mime: mime, bytes: bytes, replyTo: replyTo, filePath: path);
    await _enqueue(
      chat,
      local,
      {'body': caption, 'file_path': path, 'file_name': name, 'file_size': bytes.length, 'mime_type': mime, 'reply_to': ?replyTo},
      uploads: [(path: path, bytes: bytes, mime: mime)],
    );
    return null;
  }

  /// Tap on a red (refused) message: put it back in the queue.
  Future<void> retry(Chat chat, Message m) async {
    if (!m.failed) return;
    final it = _failedItems.remove(m.id);
    if (it == null) return;
    m
      ..failed = false
      ..pending = true;
    notifyListeners();
    _outbox.add(it);
    await _saveOutbox();
    unawaited(_drain());
  }

  /// Short-lived link to a private attachment (cached for the session).
  /// Already-known link (no network), so images can show on the first frame.
  String? cachedFileUrl(String path) => _signedUrls[path];

  Future<String?> fileUrl(String path) async {
    final cached = _signedUrls[path];
    if (cached != null) return cached;
    try {
      final url = await _sb.storage.from(AppConfig.attachmentsBucket).createSignedUrl(path, 60 * 60 * 6);
      _signedUrls[path] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  String previewOf(Message m) => RichMessageText.strip(_previewOf(m));

  String _previewOf(Message m) => m.deleted
      ? s.get('deleted')
      : m.locked
      ? s.get('locked_message')
      : switch (m.kind) {
          MsgKind.voice => s.get('voice_message'),
          MsgKind.image => m.body.isEmpty ? s.get('photo') : m.body,
          MsgKind.album => m.body.isEmpty ? s.get('album_n', {'n': localDigits('${m.albumItems.length}', lang)}) : m.body,
          MsgKind.file => m.fileName ?? s.get('file'),
          MsgKind.location => s.get('location'),
          MsgKind.contact => '${s.get('contact')}: ${m.meta?['name'] ?? ''}',
          MsgKind.text => m.body,
        };

  /// Icon shown before a message preview (chat list, reply quotes).
  IconData? previewIcon(Message m) => m.deleted
      ? Icons.block_rounded
      : m.locked
      ? Icons.lock_rounded
      : switch (m.kind) {
          MsgKind.voice => CupertinoIcons.mic_fill,
          MsgKind.image => Icons.photo_rounded,
          MsgKind.album => Icons.photo_library_rounded,
          MsgKind.file => Icons.insert_drive_file_rounded,
          MsgKind.location => Icons.location_on_rounded,
          MsgKind.contact => Icons.person_rounded,
          MsgKind.text => null,
        };

  // ── Reactions ────────────────────────────────────────────────────────────
  /// messageId → (userId → emoji)
  final Map<String, Map<String, String>> reactions = {};

  Future<void> _loadReactions(String chatId) async {
    try {
      final rows = await _sb
          .from('message_reactions')
          .select(_v9 ? 'message_id,user_id,emoji,cipher,key_id' : 'message_id,user_id,emoji')
          .eq('chat_id', chatId);
      for (final r in rows) {
        final e = await _openReaction(chatId, r);
        if (e != null) reactions.putIfAbsent(r['message_id'] as String, () => {})[r['user_id'] as String] = e;
      }
      notifyListeners();
    } catch (_) {}
  }

  /// The emoji of a reaction row (opened when it is sealed).
  Future<String?> _openReaction(String chatId, Map<String, dynamic> r) async {
    final c = r['cipher'] as String?;
    final keyId = (r['key_id'] as num?)?.toInt();
    if (c == null || keyId == null) return r['emoji'] as String?;
    final key = await _keyFor(chatId, keyId);
    if (key == null) return null;
    final p = await E2E.instance.open(key, c, chatId: chatId, msgId: 'r:${r['message_id']}', senderId: r['user_id'] as String, keyId: keyId);
    return p?['e'] as String?;
  }

  Future<void> _onReaction(PostgresChangeEvent type, Map<String, dynamic> row, Map<String, dynamic> old) async {
    if (type == PostgresChangeEvent.delete) {
      final mid = old['message_id'] as String?;
      final uid = old['user_id'] as String?;
      if (mid != null && uid != null) reactions[mid]?.remove(uid);
    } else {
      final e = await _openReaction(row['chat_id'] as String, row);
      if (e == null) return;
      reactions.putIfAbsent(row['message_id'] as String, () => {})[row['user_id'] as String] = e;
    }
    notifyListeners();
  }

  /// Same emoji again removes the reaction; another emoji replaces it.
  Future<void> react(Chat chat, Message m, String emoji) async {
    final mine = reactions[m.id]?[myId];
    final map = reactions.putIfAbsent(m.id, () => {});
    try {
      if (mine == emoji) {
        map.remove(myId);
        notifyListeners();
        await _sb.from('message_reactions').delete().eq('message_id', m.id).eq('user_id', myId!);
      } else {
        map[myId!] = emoji;
        notifyListeners();
        if (E2E.instance.ready && _v9 && !chat.isChannel) {
          // the server only sees that someone reacted, not with what
          final sk = await _sendKey(chat.id);
          final cipher = await E2E.instance.seal(sk.key, {'e': emoji}, chatId: chat.id, msgId: 'r:${m.id}', senderId: myId!, keyId: sk.id);
          await _sb.from('message_reactions').upsert({
            'message_id': m.id,
            'chat_id': chat.id,
            'user_id': myId,
            'emoji': '•',
            'cipher': cipher,
            'key_id': sk.id,
          });
        } else {
          await _sb.from('message_reactions').upsert({'message_id': m.id, 'chat_id': chat.id, 'user_id': myId, 'emoji': emoji});
        }
      }
    } catch (_) {}
  }

  // ── Edit, pin, forward ───────────────────────────────────────────────────
  Future<bool> editMessage(Chat chat, Message m, String text) async {
    final body = text.trim();
    if (body.isEmpty || m.senderId != myId) return false;
    final list = _messages[chat.id];
    final i = list?.indexWhere((x) => x.id == m.id) ?? -1;
    if (i >= 0) list![i] = m.copyWith(body: body, editedAt: DateTime.now());
    notifyListeners();
    try {
      if (m.e2e) {
        final key = await _keyFor(chat.id, m.keyId!);
        if (key == null) throw StateError('no key');
        final payload = <String, dynamic>{'b': body, 'm': m.meta, 'fn': m.fileName, 'mt': m.mimeType, 'd': m.durationMs}..removeWhere((_, v) => v == null);
        final cipher = await E2E.instance.seal(key, payload, chatId: chat.id, msgId: m.id, senderId: m.senderId, keyId: m.keyId!);
        await _sb.rpc('edit_message_e2e', params: {'m': m.id, 'new_cipher': cipher});
      } else {
        await _sb.rpc('edit_message', params: {'m': m.id, 'new_body': body});
      }
      return true;
    } catch (_) {
      if (i >= 0) list![i] = m;
      notifyListeners();
      return false;
    }
  }

  Future<void> pinMessage(Chat chat, Message? m) async {
    chat.pinnedMessageId = m?.id;
    notifyListeners();
    try {
      await _sb.rpc('set_pinned_message', params: {'c': chat.id, 'm': m?.id});
    } on PostgrestException catch (e) {
      // a server without the group update (v10)
      if (e.code == 'PGRST202') await _sb.from('chats').update({'pinned_message_id': m?.id}).eq('id', chat.id);
    } catch (_) {}
  }

  /// Copies a message (and its files) into another chat.
  /// Forwards a message (queued too, so it also works offline).
  Future<bool> forward(Message m, Chat target) async {
    if (myId == null) return false;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final copies = <({String from, String to})>[];
    String copyOf(String path) {
      final to = '${target.id}/$stamp-${copies.length}-${path.split('/').last}';
      copies.add((from: path, to: to));
      return to;
    }

    Map<String, dynamic>? meta = m.meta == null ? null : Map<String, dynamic>.from(m.meta!);
    if (m.kind == MsgKind.album && meta != null) {
      meta['items'] = [
        for (final it in m.albumItems) {...it, 'path': copyOf(it['path'] as String)},
      ];
    }
    final newPath = m.filePath == null ? null : copyOf(m.filePath!);
    final local = _local(
      target,
      m.kind,
      m.body,
      name: m.fileName,
      size: m.fileSize,
      mime: m.mimeType,
      durationMs: m.durationMs,
      meta: meta,
      filePath: newPath,
      bytes: m.localBytes,
    );
    await _enqueue(target, local, {
      'body': m.body,
      'file_path': newPath,
      'file_name': m.fileName,
      'file_size': m.fileSize,
      'mime_type': m.mimeType,
      'duration_ms': m.durationMs,
      'meta': meta,
    }, copies: copies);
    return true;
  }

  // ── Photos, albums, location, contacts ───────────────────────────────────
  static Future<({int w, int h})> imageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final r = (w: frame.image.width, h: frame.image.height);
      frame.image.dispose();
      return r;
    } catch (_) {
      return (w: 4, h: 3);
    }
  }

  /// One photo becomes an image message; several become one album.
  Future<String?> sendPhotos(Chat chat, List<({String name, Uint8List bytes})> photos, {String caption = '', String? replyTo}) async {
    if (photos.isEmpty) return null;
    if (photos.any((p) => p.bytes.length > AppConfig.maxFileBytes)) return 'too_big';
    final sizes = [for (final p in photos) await imageSize(p.bytes)];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (photos.length == 1) {
      final p = photos.first;
      final mime = mimeFor(p.name);
      final path = '${chat.id}/$stamp-${_safe(p.name)}';
      final meta = {'w': sizes.first.w, 'h': sizes.first.h};
      final local = _local(
        chat,
        MsgKind.image,
        caption,
        name: p.name,
        size: p.bytes.length,
        mime: mime,
        bytes: p.bytes,
        replyTo: replyTo,
        filePath: path,
        meta: meta,
      );
      await _enqueue(
        chat,
        local,
        {'body': caption, 'file_path': path, 'file_name': p.name, 'file_size': p.bytes.length, 'mime_type': mime, 'meta': meta, 'reply_to': ?replyTo},
        uploads: [(path: path, bytes: p.bytes, mime: mime)],
      );
      return null;
    }
    final uploads = <({String path, Uint8List bytes, String mime})>[];
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < photos.length; i++) {
      final p = photos[i];
      final path = '${chat.id}/$stamp-$i-${_safe(p.name)}';
      uploads.add((path: path, bytes: p.bytes, mime: mimeFor(p.name)));
      items.add({'path': path, 'w': sizes[i].w, 'h': sizes[i].h});
    }
    final meta = {'items': items};
    final local = _local(chat, MsgKind.album, caption, replyTo: replyTo, meta: meta, album: [for (final p in photos) p.bytes]);
    await _enqueue(chat, local, {'body': caption, 'meta': meta, 'reply_to': ?replyTo}, uploads: uploads);
    return null;
  }

  String _safe(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<void> sendLocation(Chat chat, double lat, double lng, {String? replyTo}) async {
    final meta = {'lat': lat, 'lng': lng};
    final local = _local(chat, MsgKind.location, '', meta: meta, replyTo: replyTo);
    await _enqueue(chat, local, {'meta': meta, 'reply_to': ?replyTo});
  }

  Future<void> sendContact(Chat chat, {required String name, String? phone, String? email, String? userId, String? replyTo}) async {
    final meta = {'name': name, 'phone': ?phone, 'email': ?email, 'user_id': ?userId};
    final local = _local(chat, MsgKind.contact, '', meta: meta, replyTo: replyTo);
    await _enqueue(chat, local, {'meta': meta, 'reply_to': ?replyTo});
  }

  Future<bool> setGroupPhoto(Chat chat, String name, Uint8List bytes) async {
    try {
      final path = '${chat.id}/group-${DateTime.now().millisecondsSinceEpoch}.${name.split('.').last.toLowerCase()}';
      await _sb.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeFor(name)));
      try {
        await _sb.rpc('update_group', params: {'c': chat.id, 'new_avatar_path': path});
      } on PostgrestException catch (e) {
        if (e.code != 'PGRST202') rethrow;
        await _sb.from('chats').update({'avatar_path': path}).eq('id', chat.id);
      }
      chat.avatarPath = path;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Stories ──────────────────────────────────────────────────────────────
  List<StoryUser> stories = [];

  StoryUser? get myStories {
    for (final u in stories) {
      if (u.user.id == myId) return u;
    }
    return null;
  }

  Future<void> _loadCachedStories() async {
    if (stories.isNotEmpty) return;
    // the stories seen last time, so they still open without internet
    final cached = await MediaCache.instance.store.readJson('${_cachePrefix}_stories');
    if (cached is! List || stories.isNotEmpty) return;
    try {
      final now = DateTime.now();
      stories = [
        for (final u in cached.map((e) => StoryUser.fromJson(e as Map<String, dynamic>)))
          if (u.stories.any((st) => now.difference(st.createdAt).inHours < 24)) u,
      ];
      for (final u in stories) {
        for (final st in u.stories) {
          if (st.mediaPath != null) registerFileKey('stories/${st.mediaPath}', st.key);
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadStories() async {
    if (myId == null) return;
    await _loadCachedStories();
    try {
      final data = await _openStories(await _sb.rpc('story_feed').timeout(_net) as List<dynamic>);
      stories = data.map((e) => StoryUser.fromJson(e as Map<String, dynamic>)).toList();
      unawaited(MediaCache.instance.store.writeJson('${_cachePrefix}_stories', data));
      notifyListeners();
    } catch (_) {}
  }

  /// Opens sealed stories (my copy of each story key); ones I cannot open are left out.
  Future<List<dynamic>> _openStories(List<dynamic> data) async {
    final out = <dynamic>[];
    for (final u in data.cast<Map<String, dynamic>>()) {
      final author = (u['user'] as Map)['id'] as String;
      final items = <Map<String, dynamic>>[];
      for (final it in (u['stories'] as List).cast<Map<String, dynamic>>()) {
        final c = it['cipher'] as String?;
        if (c == null) {
          items.add(it);
          continue;
        }
        final w = it['wrapped'] as String?;
        if (w == null || !E2E.instance.ready) continue;
        try {
          final pub = _trustedPub(author, await _pubOf(author));
          if (pub == null) continue;
          final key = await E2E.instance.unwrap(w, chatId: 'story-${it['id']}', keyId: 1, wrapperPub: pub);
          if (key == null) continue;
          final p = await E2E.instance.open(key, c, chatId: 'story', msgId: it['id'] as String, senderId: author, keyId: 0);
          if (p == null) continue;
          final k = E2E.b64(await key.extractBytes());
          final mp = it['media_path'] as String?;
          if (mp != null) registerFileKey('stories/$mp', k);
          items.add(
            {...it, 'body': p['b'] ?? '', 'bg': p['bg'], 'k': k}
              ..remove('cipher')
              ..remove('wrapped'),
          );
        } catch (_) {}
      }
      if (items.isNotEmpty) out.add({...u, 'stories': items});
    }
    return out;
  }

  Future<bool> postStory({Uint8List? image, String? imageName, String text = '', String? bg}) async {
    if (E2E.instance.ready && _v9) return _postSealedStory(image: image, imageName: imageName, text: text, bg: bg);
    try {
      String? path;
      if (image != null) {
        path = '${myId!}/${DateTime.now().millisecondsSinceEpoch}-${_safe(imageName ?? 'story.jpg')}';
        await _sb.storage.from('stories').uploadBinary(path, image, fileOptions: FileOptions(contentType: mimeFor(imageName ?? 'x.jpg')));
      }
      await _sb.from('stories').insert({'kind': image != null ? 'image' : 'text', 'media_path': path, 'body': text.trim(), 'bg': bg});
      await loadStories();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A story only the people who may see it can open: its text and photo are
  /// sealed with a fresh key, and each viewer gets a copy locked for them.
  Future<bool> _postSealedStory({Uint8List? image, String? imageName, String text = '', String? bg}) async {
    try {
      final id = _uuid();
      final k = E2E.newFileKey();
      final key = SecretKey(E2E.unb64(k));
      String? path;
      if (image != null) {
        path = '${myId!}/${DateTime.now().millisecondsSinceEpoch}-${_safe(imageName ?? 'story.jpg')}';
        final sealed = await E2E.sealFile(image, k);
        await _sb.storage.from('stories').uploadBinary(path, sealed, fileOptions: const FileOptions(contentType: 'application/octet-stream')).timeout(_net);
        await MediaCache.instance.store.save('stories/$path', image);
        registerFileKey('stories/$path', k);
      }
      final cipher = await E2E.instance.seal(key, {'b': text.trim(), 'bg': ?bg}, chatId: 'story', msgId: id, senderId: myId!, keyId: 0);
      await _sb.from('stories').insert({'id': id, 'kind': image != null ? 'image' : 'text', 'media_path': path, 'body': '', 'cipher': cipher}).timeout(_net);
      final audience = (await _sb.rpc('story_audience').timeout(_net) as List).cast<Map>();
      final rows = [
        for (final a in audience)
          if (_trusted(a['user_id'] as String, a['public_key'] as String))
            {
              'story_id': id,
              'viewer_id': a['user_id'],
              'wrapped': await E2E.instance.wrap(
                key,
                chatId: 'story-$id',
                keyId: 1,
                recipientId: a['user_id'] as String,
                recipientPub: a['public_key'] as String,
              ),
            },
      ];
      if (rows.isNotEmpty) await _sb.from('story_keys').insert(rows).timeout(_net);
      await loadStories();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> markStorySeen(StoryItem st) async {
    if (st.seen) return;
    st.seen = true;
    try {
      await _sb.from('story_views').insert({'story_id': st.id});
    } catch (_) {}
  }

  Future<void> deleteStory(StoryItem st) async {
    try {
      await _sb.from('stories').delete().eq('id', st.id);
      if (st.mediaPath != null) await _sb.storage.from('stories').remove([st.mediaPath!]);
    } catch (_) {}
    await loadStories();
  }

  Future<List<({Profile profile, bool liked})>> storyViewers(StoryItem st) async {
    try {
      final data = await _sb.rpc('story_viewers', params: {'s': st.id}) as List<dynamic>;
      return [for (final e in data.cast<Map<String, dynamic>>()) (profile: Profile.fromJson(e), liked: (e['liked'] as bool?) ?? false)];
    } catch (_) {
      return [];
    }
  }

  /// Heart on someone's story (also marks it seen).
  Future<void> likeStory(StoryItem st, bool liked) async {
    st.liked = liked;
    st.seen = true;
    notifyListeners();
    try {
      await _sb.rpc('like_story', params: {'s': st.id, 'v': liked});
    } catch (_) {}
  }

  final Map<String, String> _storyUrls = {};
  Future<String?> storyUrl(String path) async {
    final c = _storyUrls[path];
    if (c != null) return c;
    try {
      final url = await _sb.storage.from('stories').createSignedUrl(path, 60 * 60 * 24);
      _storyUrls[path] = url;
      return url;
    } catch (_) {
      return null;
    }
  }

  // ── Profile & settings ───────────────────────────────────────────────────
  Future<bool> updateProfile({String? displayName, String? username}) async {
    try {
      await _sb
          .from('profiles')
          .update({
            if (displayName != null) 'display_name': displayName.trim(),
            if (username != null) 'username': username.trim().isEmpty ? null : username.trim().toLowerCase().replaceAll('@', ''),
          })
          .eq('id', myId!);
      await _loadProfile();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Uploads a new profile photo (public bucket "avatars", folder = user id).
  Future<bool> uploadAvatar(String name, Uint8List bytes) async {
    if (bytes.length > 5 * 1024 * 1024) return false;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
    final path = '${myId!}/avatar-${DateTime.now().millisecondsSinceEpoch}.$ext';
    try {
      await _sb.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeFor(name)));
      final old = me?.avatarPath;
      await _sb.from('profiles').update({'avatar_path': path}).eq('id', myId!);
      if (old != null) {
        try {
          await _sb.storage.from('avatars').remove([old]);
        } catch (_) {}
      }
      await _loadProfile();
      return true;
    } catch (_) {
      return false;
    }
  }

  void setLang(AppLang l) {
    lang = l;
    _prefs.setString('lang', l.code);
    notifyListeners();
  }

  void setGlass(bool v) {
    glass = v;
    _prefs.setBool('glass2', v);
    notifyListeners();
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _prefs.setString('theme', m.name);
    notifyListeners();
  }
}

String mimeFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'zip': 'application/zip',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'mp3': 'audio/mpeg',
        'm4a': 'audio/mp4',
        'ogg': 'audio/ogg',
        'mp4': 'video/mp4',
        'apk': 'application/vnd.android.package-archive',
      }[ext] ??
      'application/octet-stream';
}

/// Makes the controller reachable from any widget.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) => (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}
