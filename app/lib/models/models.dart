import 'dart:typed_data';

/// Public URL of a profile photo in the "avatars" bucket (set at startup).
String avatarBaseUrl = '';

class Profile {
  Profile({required this.id, required this.email, required this.displayName, this.username, this.avatarPath, this.lastReadAt, this.role});

  final String id;
  final String email;
  final String displayName;
  final String? username;
  final String? avatarPath;

  String? get avatarUrl => avatarPath == null ? null : '$avatarBaseUrl/$avatarPath';
  final DateTime? lastReadAt; // only set inside a chat's member list
  final String? role;

  String get name => displayName.trim().isEmpty ? email.split('@').first : displayName;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    id: j['id'] as String,
    email: (j['email'] as String?) ?? '',
    displayName: (j['display_name'] as String?) ?? '',
    username: j['username'] as String?,
    avatarPath: j['avatar_path'] as String?,
    lastReadAt: j['last_read_at'] == null ? null : DateTime.parse(j['last_read_at'] as String).toLocal(),
    role: j['role'] as String?,
  );
}

enum MsgKind { text, image, file, voice, album, location, contact }

enum MsgStatus { sending, sent, read, failed }

class Message {
  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.kind,
    required this.body,
    required this.createdAt,
    this.filePath,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.replyTo,
    this.deletedAt,
    this.durationMs,
    this.editedAt,
    this.meta,
    this.localBytes,
    this.localAlbum,
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String chatId;
  final String senderId;
  final MsgKind kind;
  final String body;
  final DateTime createdAt;
  final String? filePath;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? replyTo;
  final DateTime? deletedAt;
  final int? durationMs;
  final DateTime? editedAt;

  /// Extra data: image size {w,h}, album {items:[{path,w,h}]},
  /// location {lat,lng,label}, contact {name,phone,email,user_id}.
  final Map<String, dynamic>? meta;

  /// Album images being uploaded (shown before the upload finishes).
  final List<Uint8List>? localAlbum;

  bool get deleted => deletedAt != null;
  bool get edited => editedAt != null;

  double? get width => (meta?['w'] as num?)?.toDouble();
  double? get height => (meta?['h'] as num?)?.toDouble();
  List<Map<String, dynamic>> get albumItems => ((meta?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Message copyWith({String? body, DateTime? editedAt, DateTime? deletedAt}) => Message(
    id: id,
    chatId: chatId,
    senderId: senderId,
    kind: kind,
    body: body ?? this.body,
    createdAt: createdAt,
    filePath: filePath,
    fileName: fileName,
    fileSize: fileSize,
    mimeType: mimeType,
    replyTo: replyTo,
    deletedAt: deletedAt ?? this.deletedAt,
    durationMs: durationMs,
    editedAt: editedAt ?? this.editedAt,
    meta: meta,
  );

  /// Bytes of a file we are uploading (shown before the upload finishes).
  final Uint8List? localBytes;
  bool pending;
  bool failed;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
    id: j['id'] as String,
    chatId: j['chat_id'] as String,
    senderId: j['sender_id'] as String,
    kind: MsgKind.values.byName((j['kind'] as String?) ?? 'text'),
    body: (j['body'] as String?) ?? '',
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    filePath: j['file_path'] as String?,
    fileName: j['file_name'] as String?,
    fileSize: (j['file_size'] as num?)?.toInt(),
    mimeType: j['mime_type'] as String?,
    replyTo: j['reply_to'] as String?,
    deletedAt: j['deleted_at'] == null ? null : DateTime.parse(j['deleted_at'] as String).toLocal(),
    durationMs: (j['duration_ms'] as num?)?.toInt(),
    editedAt: j['edited_at'] == null ? null : DateTime.parse(j['edited_at'] as String).toLocal(),
    meta: j['meta'] == null ? null : Map<String, dynamic>.from(j['meta'] as Map),
  );
}

/// One story (24-hour status).
class StoryItem {
  StoryItem({
    required this.id,
    required this.kind,
    this.mediaPath,
    required this.body,
    this.bg,
    required this.createdAt,
    required this.seen,
    this.views,
    this.liked = false,
    this.likes,
  });
  final String id, kind, body;
  final String? mediaPath, bg;
  final DateTime createdAt;
  bool seen;
  final int? views;

  /// I gave this story a heart; [likes] is the count on my own stories.
  bool liked;
  final int? likes;

  factory StoryItem.fromJson(Map<String, dynamic> j) => StoryItem(
    id: j['id'] as String,
    kind: j['kind'] as String,
    mediaPath: j['media_path'] as String?,
    body: (j['body'] as String?) ?? '',
    bg: j['bg'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
    seen: (j['seen'] as bool?) ?? false,
    views: (j['views'] as num?)?.toInt(),
    liked: (j['liked'] as bool?) ?? false,
    likes: (j['likes'] as num?)?.toInt(),
  );
}

/// All active stories of one person.
class StoryUser {
  StoryUser({required this.user, required this.stories, required this.allSeen});
  final Profile user;
  final List<StoryItem> stories;
  bool allSeen;

  factory StoryUser.fromJson(Map<String, dynamic> j) => StoryUser(
    user: Profile.fromJson(j['user'] as Map<String, dynamic>),
    stories: (j['stories'] as List).map((e) => StoryItem.fromJson(e as Map<String, dynamic>)).toList(),
    allSeen: (j['all_seen'] as bool?) ?? false,
  );
}

class CallRecord {
  CallRecord({
    required this.id,
    required this.chatId,
    required this.video,
    required this.status,
    required this.outgoing,
    required this.peerName,
    this.peerAvatar,
    required this.peerId,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
  });

  final String id, chatId, status, peerName, peerId;
  final String? peerAvatar;
  final bool video, outgoing;
  final DateTime createdAt;
  final DateTime? answeredAt, endedAt;

  Duration? get duration => (answeredAt != null && endedAt != null) ? endedAt!.difference(answeredAt!) : null;

  static DateTime? _t(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

  factory CallRecord.fromJson(Map<String, dynamic> j) {
    final outgoing = j['outgoing'] as bool;
    final name = (j['peer_name'] as String?) ?? '';
    return CallRecord(
      id: j['id'] as String,
      chatId: j['chat_id'] as String,
      video: j['video'] as bool,
      status: j['status'] as String,
      outgoing: outgoing,
      peerName: name.isEmpty ? ((j['peer_email'] as String?) ?? '').split('@').first : name,
      peerAvatar: j['peer_avatar'] as String?,
      peerId: (outgoing ? j['callee_id'] : j['caller_id']) as String,
      createdAt: _t(j['created_at'])!,
      answeredAt: _t(j['answered_at']),
      endedAt: _t(j['ended_at']),
    );
  }
}

class Chat {
  Chat({
    required this.id,
    required this.isGroup,
    this.title,
    required this.lastMessageAt,
    required this.members,
    this.lastMessage,
    this.unread = 0,
    this.avatarPath,
    this.pinnedMessageId,
    this.isSaved = false,
    this.pinnedAt,
    this.muted = false,
    this.archived = false,
    this.markedUnread = false,
    this.clearedAt,
  });

  final String id;
  final bool isGroup;

  /// "Saved Messages": a private chat with only me in it.
  final bool isSaved;

  // My own settings for this chat (other members have their own).
  DateTime? pinnedAt;
  bool muted;
  bool archived;
  bool markedUnread;
  DateTime? clearedAt;
  String? title;
  DateTime lastMessageAt;
  List<Profile> members;
  Message? lastMessage;
  int unread;
  String? avatarPath;
  String? pinnedMessageId;

  String? get avatarUrl => avatarPath == null ? null : '$avatarBaseUrl/$avatarPath';

  /// The other person in a direct chat.
  Profile? peer(String me) {
    for (final m in members) {
      if (m.id != me) return m;
    }
    return null;
  }

  String displayTitle(String me) => isGroup ? (title ?? '') : (peer(me)?.name ?? '');

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
    id: j['id'] as String,
    isGroup: j['is_group'] as bool,
    title: j['title'] as String?,
    lastMessageAt: DateTime.parse(j['last_message_at'] as String).toLocal(),
    members: ((j['members'] as List?) ?? const []).map((e) => Profile.fromJson(e as Map<String, dynamic>)).toList(),
    lastMessage: j['last_message'] == null ? null : Message.fromJson(j['last_message'] as Map<String, dynamic>),
    unread: (j['unread'] as num?)?.toInt() ?? 0,
    avatarPath: j['avatar_path'] as String?,
    pinnedMessageId: j['pinned_message_id'] as String?,
    isSaved: (j['is_saved'] as bool?) ?? false,
    pinnedAt: _date(j['pinned_at']),
    muted: (j['muted'] as bool?) ?? false,
    archived: (j['archived'] as bool?) ?? false,
    markedUnread: (j['marked_unread'] as bool?) ?? false,
    clearedAt: _date(j['cleared_at']),
  );
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();

String formatBytes(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
