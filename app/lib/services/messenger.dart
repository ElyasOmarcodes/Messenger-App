import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import 'apis.dart';
import 'relay.dart';

/// Wire format version. Bump when the envelope changes.
const _protocol = 1;

/// Central state of the app: profile, settings, chats, messages, transport.
class AppController extends ChangeNotifier {
  static const defaultRelay = 'https://ntfy.sh';
  static const topicPrefix = 'pgm1';
  static const lobbyGroupId = 'lobby';

  late SharedPreferences _prefs;
  bool ready = false;

  Profile? profile;
  AppLang lang = AppLang.ps;
  ThemeMode themeMode = ThemeMode.light;
  String relayUrl = defaultRelay;
  RelayState relayState = RelayState.offline;

  final List<Chat> chats = [];
  final Map<String, List<Message>> _messages = {};
  String? openChatId;

  final List<String> _seenOrder = [];
  final Set<String> _seen = {};
  int _lastEventTime = 0;
  Relay? _relay;
  Timer? _saveTimer;
  final Set<String> _dirtyChats = {};
  final Map<String, Map<String, MsgStatus>> _pendingAcks = {};
  Timer? _ackTimer;

  final StreamController<Message> _incoming = StreamController.broadcast();

  /// Fires for every message that arrives from someone else.
  Stream<Message> get incoming => _incoming.stream;

  Strings get s => Strings(lang);

  // ── Startup ──────────────────────────────────────────────────────────────
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    lang = AppLang.fromCode(_prefs.getString('lang'));
    themeMode = ThemeMode.values.byName(_prefs.getString('theme') ?? 'light');
    relayUrl = _prefs.getString('relay') ?? defaultRelay;
    _lastEventTime = _prefs.getInt('lastEventTime') ?? 0;
    final seen = _prefs.getStringList('seen') ?? const [];
    _seenOrder.addAll(seen);
    _seen.addAll(seen);

    final p = _prefs.getString('profile');
    if (p != null) {
      profile = Profile.fromJson(jsonDecode(p) as Map<String, dynamic>);
      final list = (jsonDecode(_prefs.getString('chats') ?? '[]') as List).cast<Map<String, dynamic>>();
      chats.addAll(list.map(Chat.fromJson));
      for (final c in chats) {
        final raw = _prefs.getString('msgs:${c.id}');
        _messages[c.id] = raw == null
            ? []
            : (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(Message.fromJson).toList();
        // Anything still "sending" from a previous run did not make it.
        for (final m in _messages[c.id]!) {
          if (m.status == MsgStatus.sending) m.status = MsgStatus.failed;
        }
      }
      _connect();
    }
    ready = true;
    notifyListeners();
  }

  String inboxTopic(String userId) => '$topicPrefix-u-$userId';
  String groupTopic(String groupId) => '$topicPrefix-g-$groupId';

  List<String> get _topics => [
        inboxTopic(profile!.id),
        for (final c in chats)
          if (c.groupId != null) groupTopic(c.groupId!),
      ];

  void _connect() {
    _relay ??= Relay(
      baseUrl: relayUrl,
      onEvent: _onEvent,
      onState: (st) {
        relayState = st;
        notifyListeners();
      },
    );
    _relay!.baseUrl = relayUrl;
    _relay!.connect(_topics, () => _lastEventTime);
  }

  // ── Onboarding ───────────────────────────────────────────────────────────
  Future<void> completeOnboarding({required String name, required String phone}) async {
    profile = Profile(id: randomId(10), name: name.trim(), phone: phone.trim(), createdAt: DateTime.now());
    await _prefs.setString('profile', jsonEncode(profile!.toJson()));
    _seed();
    _scheduleSave(all: true);
    _connect();
    notifyListeners();
  }

  void _seed() {
    final now = DateTime.now();
    Message sys(String chatId, String key, DateTime t, {String sender = 'paigham'}) => Message(
          id: randomId(12),
          chatId: chatId,
          senderId: sender,
          senderName: '§app_name',
          text: '§$key',
          time: t,
          outgoing: false,
          status: MsgStatus.read,
        );

    final news = Chat(id: 'news', kind: ChatKind.channel, title: '§news', pinned: true, unread: 3);
    _messages['news'] = [
      sys('news', 'news_1', now.subtract(const Duration(minutes: 3))),
      sys('news', 'news_2', now.subtract(const Duration(minutes: 2))),
      sys('news', 'news_3', now.subtract(const Duration(minutes: 1))),
    ];
    news.updatedAt = now.subtract(const Duration(minutes: 1));

    final lobby = Chat(id: 'g:$lobbyGroupId', kind: ChatKind.lobby, title: '§lobby', groupId: lobbyGroupId);
    _messages[lobby.id] = [
      Message(
        id: randomId(12),
        chatId: lobby.id,
        senderId: 'paigham',
        senderName: '',
        text: '§lobby_welcome',
        time: now.subtract(const Duration(minutes: 4)),
        outgoing: false,
        system: true,
      ),
    ];
    lobby.updatedAt = now.subtract(const Duration(minutes: 4));

    final bot = Chat(id: 'bot', kind: ChatKind.bot, title: '§assistant', unread: 1);
    _messages['bot'] = [sys('bot', 'bot_hello', now.subtract(const Duration(minutes: 5)), sender: 'bot')];
    bot.updatedAt = now.subtract(const Duration(minutes: 5));

    final saved = Chat(id: 'saved', kind: ChatKind.saved, title: '§saved');
    _messages['saved'] = [];
    saved.updatedAt = now.subtract(const Duration(minutes: 6));

    chats
      ..clear()
      ..addAll([news, lobby, bot, saved]);
  }

  // ── Queries ──────────────────────────────────────────────────────────────
  List<Message> messagesOf(String chatId) => _messages[chatId] ?? const [];

  Message? lastMessage(String chatId) {
    final l = _messages[chatId];
    return (l == null || l.isEmpty) ? null : l.last;
  }

  Chat? chatById(String id) {
    for (final c in chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<Chat> get sortedChats {
    final l = [...chats];
    l.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return l;
  }

  int get totalUnread => chats.fold(0, (n, c) => n + c.unread);

  /// Resolves "§key" placeholders used for built-in, translatable content.
  String display(String raw) {
    if (!raw.startsWith('§')) return raw;
    final parts = raw.substring(1).split('|');
    final args = <String, String>{};
    for (final p in parts.skip(1)) {
      final i = p.indexOf('=');
      if (i > 0) args[p.substring(0, i)] = p.substring(i + 1);
    }
    return s.get(parts.first, args);
  }

  String chatTitle(Chat c) => display(c.title);

  // ── Sending ──────────────────────────────────────────────────────────────
  Future<void> send(Chat chat, String text) async {
    final body = text.trim();
    if (body.isEmpty || profile == null || !chat.canWrite) return;
    final m = Message(
      id: randomId(12),
      chatId: chat.id,
      senderId: profile!.id,
      senderName: profile!.name,
      text: body.length > 2000 ? body.substring(0, 2000) : body,
      time: DateTime.now(),
      outgoing: true,
      status: MsgStatus.sending,
    );
    _add(chat, m);

    switch (chat.kind) {
      case ChatKind.saved:
        m.status = MsgStatus.read;
      case ChatKind.bot:
        m.status = MsgStatus.read;
        unawaited(_botReply(chat, body));
      case ChatKind.channel:
        return;
      case ChatKind.direct:
      case ChatKind.group:
      case ChatKind.lobby:
        await _transmit(chat, m);
    }
    _touch(chat);
  }

  Future<void> retry(Message m) async {
    final chat = chatById(m.chatId);
    if (chat == null || m.status != MsgStatus.failed) return;
    m.status = MsgStatus.sending;
    notifyListeners();
    await _transmit(chat, m);
    _touch(chat);
  }

  Future<void> _transmit(Chat chat, Message m) async {
    _markSeen(m.id);
    final env = {
      'v': _protocol,
      't': 'm',
      'id': m.id,
      'f': profile!.id,
      'n': profile!.name,
      'x': m.text,
      'ts': m.time.millisecondsSinceEpoch,
      if (chat.groupId != null) 'g': chat.groupId,
      if (chat.groupId != null && chat.kind == ChatKind.group) 'gn': chat.title,
    };
    final topic = chat.kind == ChatKind.direct ? inboxTopic(chat.peerId!) : groupTopic(chat.groupId!);
    final ok = await _relay!.publish(topic, jsonEncode(env));
    if (m.status == MsgStatus.sending) {
      m.status = ok ? MsgStatus.sent : MsgStatus.failed;
    }
  }

  void _add(Chat chat, Message m) {
    final list = _messages.putIfAbsent(chat.id, () => []);
    list.add(m);
    list.sort((a, b) => a.time.compareTo(b.time));
    if (list.length > 500) list.removeRange(0, list.length - 500);
    if (m.time.isAfter(chat.updatedAt)) chat.updatedAt = m.time;
    _touch(chat);
  }

  void _touch(Chat chat) {
    _dirtyChats.add(chat.id);
    _scheduleSave();
    notifyListeners();
  }

  // ── Receiving ────────────────────────────────────────────────────────────
  void _onEvent(RelayEvent e) {
    if (e.time > _lastEventTime) _lastEventTime = e.time;
    if (_seen.contains(e.id)) return;
    _markSeen(e.id);

    Map<String, dynamic> env;
    try {
      env = jsonDecode(e.body) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (env['v'] != _protocol || profile == null) return;
    final from = env['f'] as String? ?? '';
    final type = env['t'];

    if (type == 'a') {
      _onAck(from, (env['ids'] as List).cast<String>(), env['s'] == 'r' ? MsgStatus.read : MsgStatus.delivered);
      return;
    }
    if (type != 'm' && type != 'j') return;

    final id = (env['id'] as String?) ?? e.id;
    if (_seen.contains(id) && id != e.id) return;
    _markSeen(id);
    if (from == profile!.id) return; // our own echo on a group topic

    final name = ((env['n'] as String?) ?? '').trim();
    final groupId = env['g'] as String?;
    Chat? chat;
    if (groupId != null) {
      chat = chatById('g:$groupId');
      if (chat == null) return; // not a member any more
      final gn = (env['gn'] as String?)?.trim();
      if (gn != null && gn.isNotEmpty && chat.kind == ChatKind.group && chat.title != gn) chat.title = gn;
    } else {
      if (!isValidUserId(from)) return;
      chat = chatById('u:$from');
      if (chat == null) {
        chat = Chat(id: 'u:$from', kind: ChatKind.direct, title: name.isEmpty ? prettyId(from) : name, peerId: from);
        chats.add(chat);
        _subscriptionChanged();
      } else if (name.isNotEmpty && chat.title != name) {
        chat.title = name;
      }
    }

    final ts = (env['ts'] as num?)?.toInt();
    final isOpen = openChatId == chat.id;
    final m = Message(
      id: id,
      chatId: chat.id,
      senderId: from,
      senderName: name,
      text: type == 'j' ? '§joined_group|name=$name' : ((env['x'] as String?) ?? ''),
      time: ts == null ? DateTime.fromMillisecondsSinceEpoch(e.time * 1000) : DateTime.fromMillisecondsSinceEpoch(ts),
      outgoing: false,
      status: isOpen ? MsgStatus.read : MsgStatus.delivered,
      system: type == 'j',
    );
    _add(chat, m);
    if (!isOpen && !m.system) chat.unread++;
    if (chat.kind == ChatKind.direct) _queueAck(from, id, m.status);
    if (!m.system) _incoming.add(m);
    notifyListeners();
  }

  void _onAck(String from, List<String> ids, MsgStatus st) {
    final chat = chatById('u:$from');
    if (chat == null) return;
    var changed = false;
    for (final m in messagesOf(chat.id)) {
      if (m.outgoing && ids.contains(m.id) && m.status.index < st.index) {
        m.status = st;
        changed = true;
      }
    }
    if (changed) _touch(chat);
  }

  void _queueAck(String peer, String msgId, MsgStatus st) {
    _pendingAcks.putIfAbsent(peer, () => {})[msgId] = st;
    _ackTimer?.cancel();
    _ackTimer = Timer(const Duration(milliseconds: 1200), _flushAcks);
  }

  Future<void> _flushAcks() async {
    final batch = Map.of(_pendingAcks);
    _pendingAcks.clear();
    for (final entry in batch.entries) {
      for (final st in [MsgStatus.read, MsgStatus.delivered]) {
        final ids = entry.value.entries.where((e) => e.value == st).map((e) => e.key).toList();
        if (ids.isEmpty) continue;
        await _relay?.publish(
          inboxTopic(entry.key),
          jsonEncode({'v': _protocol, 't': 'a', 'f': profile!.id, 'ids': ids, 's': st == MsgStatus.read ? 'r' : 'd'}),
        );
      }
    }
  }

  void _markSeen(String id) {
    if (_seen.add(id)) {
      _seenOrder.add(id);
      if (_seenOrder.length > 3000) {
        _seen.remove(_seenOrder.removeAt(0));
      }
    }
  }

  // ── Chat actions ─────────────────────────────────────────────────────────
  void openChat(String id) {
    openChatId = id;
    final c = chatById(id);
    if (c != null) markRead(c);
  }

  void closeChat(String id) {
    if (openChatId == id) openChatId = null;
  }

  void markRead(Chat chat) {
    var changed = chat.unread != 0;
    chat.unread = 0;
    for (final m in messagesOf(chat.id)) {
      if (!m.outgoing && m.status != MsgStatus.read) {
        m.status = MsgStatus.read;
        changed = true;
        if (chat.kind == ChatKind.direct && !m.system) _queueAck(chat.peerId!, m.id, MsgStatus.read);
      }
    }
    if (changed) _touch(chat);
  }

  Chat startDirect(String peerId, {String? name}) {
    final existing = chatById('u:$peerId');
    if (existing != null) return existing;
    final c = Chat(
      id: 'u:$peerId',
      kind: ChatKind.direct,
      title: (name == null || name.trim().isEmpty) ? prettyId(peerId) : name.trim(),
      peerId: peerId,
    );
    chats.add(c);
    _messages[c.id] = [];
    _touch(c);
    _subscriptionChanged();
    return c;
  }

  Chat createGroup(String name) {
    final gid = randomId(10);
    final c = Chat(id: 'g:$gid', kind: ChatKind.group, title: name.trim(), groupId: gid);
    chats.add(c);
    _messages[c.id] = [
      Message(
        id: randomId(12),
        chatId: c.id,
        senderId: 'paigham',
        senderName: '',
        text: '§group_created',
        time: DateTime.now(),
        outgoing: false,
        status: MsgStatus.read,
        system: true,
      ),
    ];
    _touch(c);
    _subscriptionChanged();
    return c;
  }

  Future<Chat> joinGroup(String groupId) async {
    final existing = chatById('g:$groupId');
    if (existing != null) return existing;
    final c = Chat(id: 'g:$groupId', kind: ChatKind.group, title: '${s.get('group')} ${prettyId(groupId)}', groupId: groupId);
    chats.add(c);
    _messages[c.id] = [];
    _touch(c);
    _subscriptionChanged(sinceAll: true);
    final jid = randomId(12);
    _markSeen(jid);
    await _relay?.publish(
      groupTopic(groupId),
      jsonEncode({'v': _protocol, 't': 'j', 'id': jid, 'f': profile!.id, 'n': profile!.name, 'g': groupId}),
    );
    return c;
  }

  void togglePin(Chat c) {
    c.pinned = !c.pinned;
    _touch(c);
  }

  void deleteChat(Chat c) {
    chats.remove(c);
    _messages.remove(c.id);
    _prefs.remove('msgs:${c.id}');
    _scheduleSave(all: true);
    if (c.groupId != null) _subscriptionChanged();
    notifyListeners();
  }

  void _subscriptionChanged({bool sinceAll = false}) {
    if (profile == null) return;
    if (sinceAll) {
      // Fetch the cached history so a new member sees recent messages.
      _relay?.connect(_topics, () => 0);
      Future.delayed(const Duration(seconds: 5), () => _relay?.connect(_topics, () => _lastEventTime));
      return;
    }
    _relay?.connect(_topics, () => _lastEventTime);
  }

  // ── Settings ─────────────────────────────────────────────────────────────
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

  void setRelay(String url) {
    final u = url.trim().replaceAll(RegExp(r'/$'), '');
    if (Uri.tryParse(u)?.hasScheme != true) return;
    relayUrl = u;
    _prefs.setString('relay', u);
    if (profile != null) _connect();
    notifyListeners();
  }

  void updateName(String name) {
    if (profile == null || name.trim().isEmpty) return;
    profile!.name = name.trim();
    _prefs.setString('profile', jsonEncode(profile!.toJson()));
    notifyListeners();
  }

  Future<void> reset() async {
    await _relay?.close();
    _relay = null;
    await _prefs.clear();
    await _prefs.setString('lang', lang.code);
    profile = null;
    chats.clear();
    _messages.clear();
    _seen.clear();
    _seenOrder.clear();
    _lastEventTime = 0;
    relayUrl = defaultRelay;
    notifyListeners();
  }

  // ── Persistence ──────────────────────────────────────────────────────────
  bool _saveAll = false;

  void _scheduleSave({bool all = false}) {
    _saveAll |= all;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    if (profile == null) return;
    await _prefs.setString('chats', jsonEncode(chats.map((c) => c.toJson()).toList()));
    final ids = _saveAll ? chats.map((c) => c.id).toSet() : {..._dirtyChats};
    for (final id in ids) {
      final l = _messages[id];
      if (l != null) await _prefs.setString('msgs:$id', jsonEncode(l.map((m) => m.toJson()).toList()));
    }
    _dirtyChats.clear();
    _saveAll = false;
    await _prefs.setInt('lastEventTime', _lastEventTime);
    await _prefs.setStringList('seen', _seenOrder);
  }

  // ── Assistant bot ────────────────────────────────────────────────────────
  String _b(String ps, String fa, String en) => switch (lang) { AppLang.ps => ps, AppLang.fa => fa, AppLang.en => en };

  bool _has(String text, List<String> words) {
    final t = text.toLowerCase();
    return words.any(t.contains);
  }

  Future<void> _botReply(Chat chat, String text) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    String reply;
    final kabul = afghanCities.first;
    try {
      if (_has(text, ['هوا', 'weather', 'آب', 'موسم', 'havā', 'hawa'])) {
        final w = await fetchWeather(kabul);
        final lbl = weatherLabel(w.code);
        reply = _b(
          'په ${kabul.ps} کې اوس ${w.temp.round()}° دی، ${lbl.ps}. باد: ${w.wind.round()} کیلومتره په ساعت کې.',
          'در ${kabul.fa} اکنون ${w.temp.round()}° است، ${lbl.fa}. باد: ${w.wind.round()} کیلومتر در ساعت.',
          'Kabul now: ${w.temp.round()}°, ${lbl.en}. Wind ${w.wind.round()} km/h.',
        );
      } else if (_has(text, ['نرخ', 'ډالر', 'دالر', 'rate', 'usd', 'اسعار', 'پیسې', 'افغانۍ', 'afn'])) {
        final r = await fetchRates();
        String f(String code) {
          final x = r.list.firstWhere((e) => e.code == code);
          final amount = x.afn.toStringAsFixed(2);
          if (lang == AppLang.en) return '${x.unit} $code = $amount AFN';
          final unit = x.unit == 1 ? '' : '${x.unit} ';
          return '$unit${currencyName(code, lang)}: $amount ${s.get('afghani')}';
        }
        reply = '${_b('نن ورځ نرخونه:', 'نرخ‌های امروز:', "Today's rates:")}\n${f('USD')}\n${f('EUR')}\n${f('PKR')}\n${f('AED')}';
      } else if (_has(text, ['آیت', 'ایت', 'قرآن', 'quran', 'ayah', 'verse'])) {
        final a = await fetchAyah(lang, number: Random().nextInt(6236) + 1);
        reply = '${a.arabic}\n\n${a.translation}\n\n(${a.surah}: ${a.number})';
      } else if (_has(text, ['لمونځ', 'لمانځه', 'نماز', 'prayer', 'اذان', 'namaz'])) {
        final p = await fetchPrayerTimes(kabul);
        final keys = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];
        reply = '${_b('د کابل د لمانځه وختونه:', 'اوقات نماز کابل:', 'Prayer times in Kabul:')}\n'
            '${keys.map((k) => '${s.get(k)}: ${p.times[k]}').join('\n')}';
      } else if (_has(text, ['نېټه', 'نیټه', 'تاریخ', 'date', 'ورځ', 'روز'])) {
        final now = DateTime.now();
        final sep = lang == AppLang.en ? ', ' : '، ';
        reply = '${_b('نن', 'امروز', 'Today is')} ${weekdayName(now, lang)}$sep${SolarHijri.fromDate(now).format(lang)}';
      } else if (_has(text, ['سلام', 'salam', 'hello', 'hi', 'ستړي'])) {
        reply = _b(
          'وعلیکم السلام ${profile!.name}! زه مرستیال یم. له ما هوا، نرخ، آیت، لمونځ یا نېټه وپوښتئ.',
          'وعلیکم السلام ${profile!.name}! من دستیار هستم. از من آب‌وهوا، نرخ، آیه، نماز یا تاریخ بپرسید.',
          'Wa alaikum assalam ${profile!.name}! Ask me about weather, rates, a verse, prayer times or the date.',
        );
      } else {
        reply = s.get('bot_help');
      }
    } catch (_) {
      reply = s.get('load_failed');
    }
    reply = localDigits(reply, lang);
    _add(
      chat,
      Message(
        id: randomId(12),
        chatId: chat.id,
        senderId: 'bot',
        senderName: s.get('assistant'),
        text: reply,
        time: DateTime.now(),
        outgoing: false,
        status: openChatId == chat.id ? MsgStatus.read : MsgStatus.delivered,
      ),
    );
    if (openChatId != chat.id) {
      chat.unread++;
      _touch(chat);
    }
  }
}

/// Makes the controller reachable from any widget.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppController read(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<AppScope>()!.widget as AppScope).notifier!;
}
