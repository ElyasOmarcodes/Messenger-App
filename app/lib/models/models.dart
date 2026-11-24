import 'dart:math';

/// Alphabet without look-alike characters (no 0/o, 1/l/i).
const _idAlphabet = '23456789abcdefghjkmnpqrstuvwxyz';

String randomId(int length) {
  final r = Random.secure();
  return List.generate(length, (_) => _idAlphabet[r.nextInt(_idAlphabet.length)]).join();
}

/// Normalises user-typed IDs: "K7M2Q-9XA3F" -> "k7m2q9xa3f".
String normalizeId(String raw) => raw.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

bool isValidUserId(String id) => RegExp('^[$_idAlphabet]{10}\$').hasMatch(id);

/// "k7m2q9xa3f" -> "K7M2Q-9XA3F"
String prettyId(String id) =>
    id.length == 10 ? '${id.substring(0, 5)}-${id.substring(5)}'.toUpperCase() : id.toUpperCase();

class Profile {
  Profile({required this.id, required this.name, this.phone = '', required this.createdAt});

  final String id;
  String name;
  String phone;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: (j['phone'] as String?) ?? '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
      );
}

enum ChatKind { direct, group, lobby, bot, channel, saved }

class Chat {
  Chat({
    required this.id,
    required this.kind,
    required this.title,
    this.peerId,
    this.groupId,
    this.pinned = false,
    this.unread = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// Local id. direct: `u:<peerId>`, group: `g:<groupId>`, others fixed.
  final String id;
  final ChatKind kind;
  String title;
  final String? peerId;
  final String? groupId;
  bool pinned;
  int unread;
  DateTime updatedAt;

  bool get canWrite => kind != ChatKind.channel;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'peerId': peerId,
        'groupId': groupId,
        'pinned': pinned,
        'unread': unread,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
      };

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        id: j['id'] as String,
        kind: ChatKind.values.byName(j['kind'] as String),
        title: j['title'] as String,
        peerId: j['peerId'] as String?,
        groupId: j['groupId'] as String?,
        pinned: (j['pinned'] as bool?) ?? false,
        unread: (j['unread'] as int?) ?? 0,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int),
      );
}

enum MsgStatus { sending, sent, delivered, read, failed }

class Message {
  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.time,
    required this.outgoing,
    this.status = MsgStatus.sent,
    this.system = false,
  });

  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime time;
  final bool outgoing;
  MsgStatus status;

  /// Centered grey notice ("Ahmad joined the group").
  final bool system;

  Map<String, dynamic> toJson() => {
        'id': id,
        'chatId': chatId,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'time': time.millisecondsSinceEpoch,
        'outgoing': outgoing,
        'status': status.name,
        'system': system,
      };

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        chatId: j['chatId'] as String,
        senderId: j['senderId'] as String,
        senderName: j['senderName'] as String,
        text: j['text'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(j['time'] as int),
        outgoing: j['outgoing'] as bool,
        status: MsgStatus.values.byName(j['status'] as String),
        system: (j['system'] as bool?) ?? false,
      );
}
