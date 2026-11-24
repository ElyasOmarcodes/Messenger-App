import 'dart:async';
import 'dart:typed_data';

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
      final res = await _sb.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
        data: {'display_name': name.trim()},
      );
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
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (p) => _onMessage(Message.fromJson(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          callback: (p) => _onMessageUpdate(Message.fromJson(p.newRecord)),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'chat_members',
          callback: (p) => _onMemberUpdate(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_members',
          callback: (_) => _scheduleReload(),
        )
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
      _incoming.add(m);
      if (!foreground || openChatId != m.chatId) _notify(chat, m);
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
    if (chat == null || row['last_read_at'] == null) return;
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

  void _sortChats() => chats.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));

  Chat? chatById(String id) {
    for (final c in chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  int get totalUnread => chats.fold(0, (n, c) => n + c.unread);

  String chatTitle(Chat c) => c.displayTitle(myId ?? '');

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

  Future<Chat?> createGroup(String title, List<Profile> members) async {
    final id = await _sb.rpc('create_group', params: {
      'title': title.trim(),
      'members': members.map((m) => m.id).toList(),
    }) as String;
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
    try {
      final rows = await _sb
          .from('messages')
          .select()
          .eq('chat_id', chatId)
          .order('created_at', ascending: false)
          .limit(300);
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

  Message _local(Chat chat, MsgKind kind, String body,
      {String? name, int? size, String? mime, Uint8List? bytes, String? replyTo, int? durationMs}) {
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

  Future<void> sendText(Chat chat, String text, {String? replyTo}) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final local = _local(chat, MsgKind.text, body.length > 4000 ? body.substring(0, 4000) : body, replyTo: replyTo);
    await _insert(chat, local, {'body': local.body, 'reply_to': ?replyTo});
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
      final row = await _sb
          .from('messages')
          .insert({'chat_id': chat.id, 'sender_id': myId, 'kind': local.kind.name, ...fields})
          .select()
          .single();
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
    await _insert(chat, local, {
      'body': caption,
      'file_path': path,
      'file_name': name,
      'file_size': bytes.length,
      'mime_type': mime,
      'reply_to': ?replyTo,
    });
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

  String previewOf(Message m) => m.deleted ? s.get('deleted') : switch (m.kind) {
        MsgKind.voice => s.get('voice_message'),
        MsgKind.image => m.body.isEmpty ? s.get('photo') : m.body,
        MsgKind.file => m.fileName ?? s.get('file'),
        MsgKind.text => m.body,
      };

  /// Icon shown before a message preview (chat list, reply quotes).
  IconData? previewIcon(Message m) => m.deleted
      ? Icons.block_rounded
      : switch (m.kind) {
          MsgKind.voice => Icons.mic_rounded,
          MsgKind.image => Icons.photo_rounded,
          MsgKind.file => Icons.insert_drive_file_rounded,
          MsgKind.text => null,
        };

  // ── Profile & settings ───────────────────────────────────────────────────
  Future<bool> updateProfile({String? displayName, String? username}) async {
    try {
      await _sb.from('profiles').update({
        if (displayName != null) 'display_name': displayName.trim(),
        if (username != null) 'username': username.trim().isEmpty ? null : username.trim().toLowerCase().replaceAll('@', ''),
      }).eq('id', myId!);
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

  void setTheme(ThemeMode m) {
    themeMode = m;
    _prefs.setString('theme', m.name);
    notifyListeners();
  }
}

String mimeFor(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return const {
        'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif', 'webp': 'image/webp',
        'pdf': 'application/pdf', 'txt': 'text/plain', 'zip': 'application/zip', 'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'ogg': 'audio/ogg', 'mp4': 'video/mp4',
        'apk': 'application/vnd.android.package-archive',
      }[ext] ??
      'application/octet-stream';
}

/// Makes the controller reachable from any widget.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child}) : super(notifier: controller);

  static AppController of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}
