import 'dart:typed_data';

class Profile {
  Profile({required this.id, required this.email, required this.displayName, this.username, this.lastReadAt, this.role});

  final String id;
  final String email;
  final String displayName;
  final String? username;
  final DateTime? lastReadAt; // only set inside a chat's member list
  final String? role;

  String get name => displayName.trim().isEmpty ? email.split('@').first : displayName;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        email: (j['email'] as String?) ?? '',
        displayName: (j['display_name'] as String?) ?? '',
        username: j['username'] as String?,
        lastReadAt: j['last_read_at'] == null ? null : DateTime.parse(j['last_read_at'] as String).toLocal(),
        role: j['role'] as String?,
      );
}

enum MsgKind { text, image, file }

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
    this.localBytes,
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
      );
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
  });

  final String id;
  final bool isGroup;
  String? title;
  DateTime lastMessageAt;
  List<Profile> members;
  Message? lastMessage;
  int unread;

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
      );
}

String formatBytes(int? b) {
  if (b == null) return '';
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}
