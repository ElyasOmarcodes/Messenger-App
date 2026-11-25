import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'notifier.dart';

/// Result of an auth call: null on success, otherwise a translation key.
typedef AuthError = String?;

/// Central app state: account, chats, messages, realtime and settings.
/// Backend: Supabase (Postgres + Auth + Realtime + Storage).
class AppController extends ChangeNotifier with WidgetsBindingObserver {
  late SharedPreferences _prefs;
  bool ready = false;

  AppLang lang = AppLang.ps;
  ThemeMode themeMode = ThemeMode.system;

  /// Glass (blur) effects; can be turned off on slow phones, like Telegram.
  bool glass = true;

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
    foreground = state == AppLifecycleState.resumed;
    if (foreground && myId != null) _scheduleReload();
  }

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    avatarBaseUrl = '${AppConfig.supabaseUrl}/storage/v1/object/public/avatars';
    _prefs = await SharedPreferences.getInstance();
    lang = AppLang.fromCode(_prefs.getString('lang'));
    themeMode = ThemeMode.values.byName(_prefs.getString('theme') ?? 'system');
    glass = _prefs.getBool('glass') ?? true;
    if (AppConfig.configured) {
      _authSub = _sb.auth.onAuthStateChange.listen((st) {
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

  Future<void> signOut() => _sb.auth.signOut();

  Future<void> _onSignedIn() async {
    await _loadProfile();
    await reloadChats();
    unawaited(loadStories());
    _subscribe();
  }

  void _onSignedOut() {
    _channel?.unsubscribe();
    _channel = null;
    me = null;
    chats = [];
    chatsLoaded = false;
    _messages.clear();
    _signedUrls.clear();
    openChatId = null;
    realtimeOnline = false;
  }

  Future<void> _loadProfile() async {
    try {
      final row = await _sb.from('profiles').select().eq('id', myId!).single();
      me = Profile.fromJson(row);
      notifyListeners();
    } catch (_) {}
  }

  // ── Realtime ─────────────────────────────────────────────────────────────
  void _subscribe() {
    _channel?.unsubscribe();
    _channel = _sb
        .channel('paigham-${myId!}')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'messages', callback: (p) => _onMessage(Message.fromJson(p.newRecord)))
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (p) => _onMessageUpdate(Message.fromJson(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (p) => _onReaction(p.eventType, p.newRecord, p.oldRecord),
        )
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'stories', callback: (_) => loadStories())
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'chats', callback: (_) => _scheduleReload())
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'chat_members', callback: (p) => _onMemberUpdate(p.newRecord))
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

  void _onMessage(Message m) {
    final list = _messages[m.chatId];
    if (list != null && !list.any((x) => x.id == m.id)) {
      // Our own message may still be shown as a pending local copy; _replace handles it.
      if (m.senderId != myId) list.add(m);
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
      if (!chat.muted) {
        _incoming.add(m);
        if (!foreground || openChatId != m.chatId) _notify(chat, m);
      }
    }
    _sortChats();
    notifyListeners();
  }

  void _notify(Chat chat, Message m) {
    if (foreground) return; // in-app banner is shown instead
    final sender = memberById(chat, m.senderId)?.name ?? '';
    Notifier.instance.show(
      id: chat.id.hashCode & 0x7fffffff,
      title: chat.isGroup ? '${chatTitle(chat)} · $sender' : sender,
      body: previewOf(m),
      payload: 'chat:${chat.id}',
    );
  }

  void _onMessageUpdate(Message m) {
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
  Future<void> deleteMessage(Chat chat, Message m) async {
    if (m.senderId != myId) return;
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
            ? Profile(id: m.id, email: m.email, displayName: m.displayName, username: m.username, avatarPath: m.avatarPath, lastReadAt: at, role: m.role)
            : m,
    ];
    notifyListeners();
  }

  void _scheduleReload() {
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 300), reloadChats);
  }

  // ── Chats ────────────────────────────────────────────────────────────────
  Future<void> reloadChats() async {
    if (myId == null) return;
    try {
      final data = await _sb.rpc('my_chats') as List<dynamic>;
      chats = data.map((e) => Chat.fromJson(e as Map<String, dynamic>)).toList();
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

  // ── Messages ─────────────────────────────────────────────────────────────
  List<Message>? messagesOf(String chatId) => _messages[chatId];

  Future<void> loadMessages(String chatId) async {
    unawaited(_loadReactions(chatId));
    try {
      final cleared = chatById(chatId)?.clearedAt;
      var q = _sb.from('messages').select().eq('chat_id', chatId);
      if (cleared != null) q = q.gt('created_at', cleared.toUtc().toIso8601String());
      final rows = await q.order('created_at', ascending: false).limit(300);
      final list = rows.map(Message.fromJson).toList().reversed.toList();
      for (final m in _messages[chatId] ?? const <Message>[]) {
        if (!list.any((x) => x.id == m.id)) list.add(m); // keep pending/realtime ones
      }
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      _messages[chatId] = list;
    } catch (_) {
      _messages.putIfAbsent(chatId, () => []);
    }
    notifyListeners();
  }

  void openChat(String id) {
    openChatId = id;
    if (_messages[id] == null) loadMessages(id);
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
  }) {
    final m = Message(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      chatId: chat.id,
      senderId: myId!,
      kind: kind,
      body: body,
      createdAt: DateTime.now(),
      fileName: name,
      fileSize: size,
      mimeType: mime,
      replyTo: replyTo,
      durationMs: durationMs,
      localBytes: bytes,
      meta: meta,
      pending: true,
    );
    _messages.putIfAbsent(chat.id, () => []).add(m);
    notifyListeners();
    return m;
  }

  void _replace(Chat chat, Message local, Message saved) {
    final list = _messages.putIfAbsent(chat.id, () => []);
    list.removeWhere((x) => x.id == saved.id);
    final i = list.indexOf(local);
    if (i >= 0) {
      list[i] = saved;
    } else {
      list.add(saved);
    }
    chat.lastMessage = saved;
    chat.lastMessageAt = saved.createdAt;
    _sortChats();
    notifyListeners();
  }

  Future<void> sendText(Chat chat, String text, {String? replyTo, Map<String, dynamic>? meta}) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final local = _local(chat, MsgKind.text, body.length > 4000 ? body.substring(0, 4000) : body, replyTo: replyTo, meta: meta);
    await _insert(chat, local, {'body': local.body, 'reply_to': ?replyTo, 'meta': ?meta});
  }

  /// Uploads a recorded voice note and posts it.
  Future<void> sendVoice(Chat chat, {required Uint8List bytes, required int durationMs, required String ext, String? replyTo}) async {
    if (bytes.isEmpty) return;
    final mime = ext == 'm4a' ? 'audio/mp4' : (ext == 'wav' ? 'audio/wav' : 'audio/webm');
    final name = 'voice-${DateTime.now().millisecondsSinceEpoch}.$ext';
    final local = _local(chat, MsgKind.voice, '', name: name, size: bytes.length, mime: mime, bytes: bytes, replyTo: replyTo, durationMs: durationMs);
    final path = '${chat.id}/$name';
    try {
      await _sb.storage.from(AppConfig.attachmentsBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    } catch (_) {
      local
        ..pending = false
        ..failed = true;
      notifyListeners();
      return;
    }
    await _insert(chat, local, {
      'file_path': path,
      'file_name': name,
      'file_size': bytes.length,
      'mime_type': mime,
      'duration_ms': durationMs,
      'reply_to': ?replyTo,
    });
  }

  Future<void> _insert(Chat chat, Message local, Map<String, dynamic> fields) async {
    try {
      final row = await _sb.from('messages').insert({'chat_id': chat.id, 'sender_id': myId, 'kind': local.kind.name, ...fields}).select().single();
      _replace(chat, local, Message.fromJson(row));
    } catch (_) {
      local
        ..pending = false
        ..failed = true;
      notifyListeners();
    }
  }

  /// Uploads a photo or file to private storage, then posts the message.
  /// Returns a translation key for client-side errors.
  Future<String?> sendFile(Chat chat, {required String name, required Uint8List bytes, String caption = '', String? replyTo}) async {
    if (bytes.length > AppConfig.maxFileBytes) return 'too_big';
    final mime = mimeFor(name);
    final kind = mime.startsWith('image/') ? MsgKind.image : MsgKind.file;
    final local = _local(chat, kind, caption, name: name, size: bytes.length, mime: mime, bytes: bytes, replyTo: replyTo);
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '${chat.id}/${DateTime.now().millisecondsSinceEpoch}-$safe';
    try {
      await _sb.storage.from(AppConfig.attachmentsBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
    } catch (_) {
      local
        ..pending = false
        ..failed = true;
      notifyListeners();
      return null;
    }
    await _insert(chat, local, {'body': caption, 'file_path': path, 'file_name': name, 'file_size': bytes.length, 'mime_type': mime, 'reply_to': ?replyTo});
    return null;
  }

  Future<void> retry(Chat chat, Message m) async {
    if (!m.failed) return;
    _messages[chat.id]?.remove(m);
    if (m.kind == MsgKind.text) {
      await sendText(chat, m.body, replyTo: m.replyTo);
    } else if (m.kind == MsgKind.voice && m.localBytes != null) {
      await sendVoice(chat, bytes: m.localBytes!, durationMs: m.durationMs ?? 0, ext: (m.fileName ?? 'x.webm').split('.').last, replyTo: m.replyTo);
    } else if (m.localBytes != null) {
      await sendFile(chat, name: m.fileName ?? 'file', bytes: m.localBytes!, caption: m.body);
    }
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

  String previewOf(Message m) => m.deleted
      ? s.get('deleted')
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
      : switch (m.kind) {
          MsgKind.voice => Icons.mic_rounded,
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
      final rows = await _sb.from('message_reactions').select('message_id,user_id,emoji').eq('chat_id', chatId);
      for (final r in rows) {
        reactions.putIfAbsent(r['message_id'] as String, () => {})[r['user_id'] as String] = r['emoji'] as String;
      }
      notifyListeners();
    } catch (_) {}
  }

  void _onReaction(PostgresChangeEvent type, Map<String, dynamic> row, Map<String, dynamic> old) {
    if (type == PostgresChangeEvent.delete) {
      final mid = old['message_id'] as String?;
      final uid = old['user_id'] as String?;
      if (mid != null && uid != null) reactions[mid]?.remove(uid);
    } else {
      reactions.putIfAbsent(row['message_id'] as String, () => {})[row['user_id'] as String] = row['emoji'] as String;
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
        await _sb.from('message_reactions').upsert({'message_id': m.id, 'chat_id': chat.id, 'user_id': myId, 'emoji': emoji});
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
      await _sb.rpc('edit_message', params: {'m': m.id, 'new_body': body});
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
      await _sb.from('chats').update({'pinned_message_id': m?.id}).eq('id', chat.id);
    } catch (_) {}
  }

  /// Copies a message (and its files) into another chat.
  Future<bool> forward(Message m, Chat target) async {
    try {
      Future<String> copy(String path) async {
        final name = path.split('/').last;
        final dst = '${target.id}/${DateTime.now().microsecondsSinceEpoch}-$name';
        await _sb.storage.from(AppConfig.attachmentsBucket).copy(path, dst);
        return dst;
      }

      Map<String, dynamic>? meta = m.meta == null ? null : Map<String, dynamic>.from(m.meta!);
      if (m.kind == MsgKind.album) {
        meta!['items'] = [
          for (final it in m.albumItems) {...it, 'path': await copy(it['path'] as String)},
        ];
      }
      final row = await _sb
          .from('messages')
          .insert({
            'chat_id': target.id,
            'sender_id': myId,
            'kind': m.kind.name,
            'body': m.body,
            'file_path': m.filePath == null ? null : await copy(m.filePath!),
            'file_name': m.fileName,
            'file_size': m.fileSize,
            'mime_type': m.mimeType,
            'duration_ms': m.durationMs,
            'meta': meta,
          })
          .select()
          .single();
      final saved = Message.fromJson(row);
      _messages[target.id]?.add(saved);
      target.lastMessage = saved;
      target.lastMessageAt = saved.createdAt;
      _sortChats();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
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
    if (photos.length == 1) {
      final p = photos.first;
      final mime = mimeFor(p.name);
      final local = _local(chat, MsgKind.image, caption, name: p.name, size: p.bytes.length, mime: mime, bytes: p.bytes, replyTo: replyTo);
      final path = '${chat.id}/${DateTime.now().millisecondsSinceEpoch}-${_safe(p.name)}';
      if (!await _upload(local, path, p.bytes, mime)) return null;
      await _insert(chat, local, {
        'body': caption,
        'file_path': path,
        'file_name': p.name,
        'file_size': p.bytes.length,
        'mime_type': mime,
        'meta': {'w': sizes.first.w, 'h': sizes.first.h},
        'reply_to': ?replyTo,
      });
      return null;
    }
    final local = Message(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      chatId: chat.id,
      senderId: myId!,
      kind: MsgKind.album,
      body: caption,
      createdAt: DateTime.now(),
      replyTo: replyTo,
      meta: {
        'items': [
          for (final z in sizes) {'w': z.w, 'h': z.h},
        ],
      },
      localAlbum: [for (final p in photos) p.bytes],
      pending: true,
    );
    _messages.putIfAbsent(chat.id, () => []).add(local);
    notifyListeners();
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < photos.length; i++) {
      final p = photos[i];
      final path = '${chat.id}/${DateTime.now().millisecondsSinceEpoch}-$i-${_safe(p.name)}';
      if (!await _upload(local, path, p.bytes, mimeFor(p.name))) return null;
      items.add({'path': path, 'w': sizes[i].w, 'h': sizes[i].h});
    }
    await _insert(chat, local, {
      'body': caption,
      'meta': {'items': items},
      'reply_to': ?replyTo,
    });
    return null;
  }

  String _safe(String name) => name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  Future<bool> _upload(Message local, String path, Uint8List bytes, String mime) async {
    try {
      await _sb.storage.from(AppConfig.attachmentsBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime));
      return true;
    } catch (_) {
      local
        ..pending = false
        ..failed = true;
      notifyListeners();
      return false;
    }
  }

  Future<void> sendLocation(Chat chat, double lat, double lng, {String? replyTo}) async {
    final meta = {'lat': lat, 'lng': lng};
    final local = Message(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      chatId: chat.id,
      senderId: myId!,
      kind: MsgKind.location,
      body: '',
      createdAt: DateTime.now(),
      meta: meta,
      replyTo: replyTo,
      pending: true,
    );
    _messages.putIfAbsent(chat.id, () => []).add(local);
    notifyListeners();
    await _insert(chat, local, {'meta': meta, 'reply_to': ?replyTo});
  }

  Future<void> sendContact(Chat chat, {required String name, String? phone, String? email, String? userId, String? replyTo}) async {
    final meta = {'name': name, 'phone': ?phone, 'email': ?email, 'user_id': ?userId};
    final local = Message(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      chatId: chat.id,
      senderId: myId!,
      kind: MsgKind.contact,
      body: '',
      createdAt: DateTime.now(),
      meta: meta,
      replyTo: replyTo,
      pending: true,
    );
    _messages.putIfAbsent(chat.id, () => []).add(local);
    notifyListeners();
    await _insert(chat, local, {'meta': meta, 'reply_to': ?replyTo});
  }

  Future<bool> setGroupPhoto(Chat chat, String name, Uint8List bytes) async {
    try {
      final path = '${chat.id}/group-${DateTime.now().millisecondsSinceEpoch}.${name.split('.').last.toLowerCase()}';
      await _sb.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeFor(name)));
      await _sb.from('chats').update({'avatar_path': path}).eq('id', chat.id);
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

  Future<void> loadStories() async {
    if (myId == null) return;
    try {
      final data = await _sb.rpc('story_feed') as List<dynamic>;
      stories = data.map((e) => StoryUser.fromJson(e as Map<String, dynamic>)).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> postStory({Uint8List? image, String? imageName, String text = '', String? bg}) async {
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

  Future<List<Profile>> storyViewers(StoryItem st) async {
    try {
      final data = await _sb.rpc('story_viewers', params: {'s': st.id}) as List<dynamic>;
      return data.map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
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
    _prefs.setBool('glass', v);
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
