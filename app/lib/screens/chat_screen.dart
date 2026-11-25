import 'dart:async';
import 'dart:math' as math;

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../config.dart';
import '../l10n/afghan_date.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../services/messenger.dart';
import '../services/voice_io.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_options.dart';
import '../widgets/effects.dart';
import '../widgets/message_bubble.dart';
import 'call_screen.dart';
import 'new_chat_sheet.dart';
import 'profile_screen.dart';

/// Opens "Saved Messages" (creating it the first time).
Future<void> openSavedMessages(BuildContext context) async {
  final c = await AppScope.read(context).savedChat();
  if (c != null && context.mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId, this.embedded = false});
  final String chatId;

  /// True when shown as the right-hand pane on wide screens.
  final bool embedded;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _bottomKey = GlobalKey();
  AppController? _app;
  bool _canSend = false;
  bool _emoji = false;
  double _bottomH = 72;

  Message? _replyTo;
  Message? _editing;

  // Delete animation bookkeeping.
  final Map<String, GlobalKey<DissolvableState>> _keys = {};
  final _listCtl = ScrollController();

  /// The message just jumped to glows for a moment.
  final _flash = ValueNotifier<String?>(null);
  final Set<String> _dissolving = {};
  final Set<String> _shown = {};
  final Set<String> _gone = {};

  // Voice note, Telegram style: hold to record, slide to cancel, slide up to lock.
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _locked = false;
  double _slideX = 0, _slideY = 0;
  DateTime? _recStart;
  Timer? _recTick;
  String _recExt = 'm4a';

  static const _emojiHeight = 300.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app == null) {
      _app = AppScope.read(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => _app!.openChat(widget.chatId));
    }
  }

  @override
  void dispose() {
    _app?.closeChat(widget.chatId);
    _input.dispose();
    _focus.dispose();
    _listCtl.dispose();
    _flash.dispose();
    _recTick?.cancel();
    _holdTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _toast(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr(key)), duration: const Duration(seconds: 2)));
  }

  void _measureBottom() {
    final box = _bottomKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final h = box.size.height;
    if ((h - _bottomH).abs() > 0.5 && mounted) setState(() => _bottomH = h);
  }

  // ── Sending ──────────────────────────────────────────────────────────────
  Future<void> _send(Chat chat) async {
    final t = _input.text;
    if (t.trim().isEmpty) return;
    if (_editing != null) {
      final m = _editing!;
      _input.clear();
      setState(() {
        _editing = null;
        _canSend = false;
      });
      if (t.trim() != m.body.trim() && !await _app!.editMessage(chat, m, t)) _toast('err_generic');
      return;
    }
    _input.clear();
    final reply = _replyTo?.id;
    setState(() {
      _canSend = false;
      _replyTo = null;
    });
    _app!.sendText(chat, t, replyTo: reply);
    _toBottom();
    if (!_emoji) _focus.requestFocus();
  }

  /// After sending, show the newest message (like Telegram).
  void _toBottom() {
    if (!_listCtl.hasClients || _listCtl.offset <= 0) return;
    _listCtl.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  String? _takeReply() {
    _toBottom();
    final r = _replyTo?.id;
    if (r != null) setState(() => _replyTo = null);
    return r;
  }

  Future<void> _pickPhotos(Chat chat, {required bool camera}) async {
    final picker = ImagePicker();
    List<XFile> files;
    try {
      if (camera) {
        final f = await picker.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2560);
        files = f == null ? [] : [f];
      } else {
        files = await picker.pickMultiImage(imageQuality: 85, maxWidth: 2560, limit: 10);
      }
    } catch (_) {
      _toast(camera ? 'camera_failed' : 'err_generic');
      return;
    }
    if (files.isEmpty) return;
    final photos = <({String name, Uint8List bytes})>[for (final f in files.take(10)) (name: f.name, bytes: await f.readAsBytes())];
    final caption = _input.text.trim();
    if (caption.isNotEmpty) {
      _input.clear();
      setState(() => _canSend = false);
    }
    final err = await _app!.sendPhotos(chat, photos, caption: caption, replyTo: _takeReply());
    if (err != null) _toast(err);
  }

  Future<void> _pickFile(Chat chat) async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty) return;
    final f = files.first;
    final size = await f.length();
    if (size != null && size > AppConfig.maxFileBytes) return _toast('too_big');
    final bytes = await f.readAsBytes();
    final err = await _app!.sendFile(chat, name: f.name, bytes: bytes, replyTo: _takeReply());
    if (err != null) _toast(err);
  }

  Future<void> _shareLocation(Chat chat) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return _toast('location_denied');
      _toast('locating');
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      await _app!.sendLocation(chat, pos.latitude, pos.longitude, replyTo: _takeReply());
    } catch (_) {
      _toast('location_failed');
    }
  }

  Future<void> _shareContact(Chat chat) async {
    final app = _app!;
    final people = <String, Profile>{};
    for (final c in app.chats) {
      for (final m in c.members) {
        if (m.id != app.myId) people[m.id] = m;
      }
    }
    final name = TextEditingController(), phone = TextEditingController();
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            children: [
              Text(ctx.tr('share_contact'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final p in people.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(seed: p.id, label: p.name, imageUrl: p.avatarUrl, size: 44),
                  title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(p.username != null ? '@${p.username}' : p.email),
                  onTap: () => Navigator.pop(ctx, p),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.dialpad_rounded, color: Theme.of(ctx).colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(ctx.tr('phone_contact'), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: ctx.tr('contact_name')),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: ctx.tr('phone_number'), hintText: '+93 7XX XXX XXX'),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () {
                  if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
                  Navigator.pop(ctx, (name.text.trim(), phone.text.trim()));
                },
                child: Text(ctx.tr('send')),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked is Profile) {
      await app.sendContact(chat, name: picked.name, email: picked.email, userId: picked.id, replyTo: _takeReply());
    } else if (picked is (String, String)) {
      await app.sendContact(chat, name: picked.$1, phone: picked.$2, replyTo: _takeReply());
    }
  }

  void _attachMenu(Chat chat) {
    FocusManager.instance.primaryFocus?.unfocus();
    final items = <(IconData, Color, String, VoidCallback)>[
      (Icons.photo_library_rounded, const Color(0xFF3390EC), 'gallery', () => _pickPhotos(chat, camera: false)),
      (Icons.photo_camera_rounded, const Color(0xFF8E6CEF), 'camera', () => _pickPhotos(chat, camera: true)),
      (Icons.insert_drive_file_rounded, const Color(0xFF2AA3C8), 'attach_file', () => _pickFile(chat)),
      (Icons.location_on_rounded, const Color(0xFF31B545), 'location', () => _shareLocation(chat)),
      (Icons.person_rounded, const Color(0xFFF5A64B), 'contact', () => _shareContact(chat)),
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 18),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            runSpacing: 16,
            children: [
              for (final (icon, color, key, action) in items)
                SizedBox(
                  width: 74,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.pop(ctx);
                      action();
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          child: Icon(icon, color: Colors.white, size: 28),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          ctx.tr(key),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Voice (Telegram gestures) ────────────────────────────────────────────
  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) return _toast('mic_denied');
      // AAC (.m4a) on phones/desktop; Opus/WebM in browsers.
      final aac = !kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.aacLc);
      _recExt = aac ? 'm4a' : 'webm';
      final config = RecordConfig(encoder: aac ? AudioEncoder.aacLc : AudioEncoder.opus, bitRate: 48000, sampleRate: 44100, numChannels: 1);
      await _recorder.start(config, path: await recordingPath(_recExt));
      HapticFeedback.mediumImpact();
      _recStart = DateTime.now();
      _recTick?.cancel();
      _recTick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _recording = true;
        _locked = false;
        _slideX = 0;
        _slideY = 0;
      });
    } catch (_) {
      _toast('mic_denied');
    }
  }

  Future<void> _stopRecording(Chat chat, {required bool send}) async {
    if (!_recording) return;
    _recTick?.cancel();
    final ms = DateTime.now().difference(_recStart ?? DateTime.now()).inMilliseconds;
    setState(() {
      _recording = false;
      _locked = false;
      _slideX = 0;
      _slideY = 0;
    });
    final out = await _recorder.stop();
    if (!send) {
      HapticFeedback.lightImpact();
      return;
    }
    if (out == null || ms < 700) return _toast('hold_to_record');
    final bytes = await readRecording(out);
    await _app!.sendVoice(chat, bytes: bytes, durationMs: ms, ext: _recExt, replyTo: _takeReply());
  }

  // Raw touch on the mic (no long-press delay): a short hold starts recording.
  Offset? _downPos;
  Timer? _holdTimer;
  bool _pressing = false;
  bool _starting = false;
  bool _releasedWhileStarting = false;

  void _micDown(PointerDownEvent e) {
    if (_recording) return;
    _downPos = e.position;
    _pressing = true;
    HapticFeedback.selectionClick();
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 150), () async {
      if (!_pressing || !mounted) return;
      _starting = true;
      _releasedWhileStarting = false;
      await _startRecording();
      _starting = false;
      if (_releasedWhileStarting && _recording && !_locked) {
        final chat = _app!.chatById(widget.chatId);
        if (chat != null) await _stopRecording(chat, send: true);
      }
    });
  }

  void _micMove(PointerMoveEvent e, Chat chat) {
    final d = _downPos;
    if (d == null) return;
    _onMicMove(e.position - d, chat);
  }

  void _micUp(Chat chat, {required bool cancelled}) {
    final wasHold = _pressing;
    _pressing = false;
    _downPos = null;
    _holdTimer?.cancel();
    if (_starting) {
      _releasedWhileStarting = !cancelled;
      return;
    }
    if (_recording && !_locked) {
      _stopRecording(chat, send: !cancelled);
    } else if (!_recording && wasHold && !cancelled) {
      _toast('hold_to_record');
    }
  }

  void _onMicMove(Offset offset, Chat chat) {
    if (!_recording || _locked) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Distance toward the start edge cancels; upward locks.
    final toStart = rtl ? offset.dx : -offset.dx;
    setState(() {
      _slideX = toStart.clamp(0.0, 200.0);
      _slideY = (-offset.dy).clamp(0.0, 140.0);
    });
    if (_slideX > 130) {
      _stopRecording(chat, send: false);
    } else if (_slideY > 90) {
      HapticFeedback.mediumImpact();
      setState(() => _locked = true);
    }
  }

  // ── Message actions ──────────────────────────────────────────────────────
  Future<void> _onAction(Chat chat, Message m, MsgAction a) async {
    switch (a) {
      case MsgAction.reply:
        setState(() {
          if (_editing != null) _input.clear();
          _replyTo = m;
          _editing = null;
        });
        if (!_emoji) _focus.requestFocus();
      case MsgAction.edit:
        setState(() {
          _editing = m;
          _replyTo = null;
          _input.text = m.body;
          _input.selection = TextSelection.collapsed(offset: m.body.length);
          _canSend = m.body.isNotEmpty;
        });
        _focus.requestFocus();
      case MsgAction.pin:
        await _app!.pinMessage(chat, chat.pinnedMessageId == m.id ? null : m);
        _toast(chat.pinnedMessageId == null ? 'unpinned' : 'pinned');
      case MsgAction.save:
        final saved = await _app!.savedChat();
        final ok = saved != null && await _app!.forward(m, saved);
        _toast(ok ? 'saved_toast' : 'err_generic');
      case MsgAction.forward:
        final target = await _pickChat();
        if (target != null) {
          final ok = await _app!.forward(m, target);
          _toast(ok ? 'forwarded' : 'err_generic');
        }
      case MsgAction.delete:
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(d.tr('delete_message')),
            content: Text(d.tr('delete_q')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
              TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(d.tr('delete'), style: const TextStyle(color: Brand.pomegranate)),
              ),
            ],
          ),
        );
        if (ok != true) return;
        if (_replyTo?.id == m.id || _editing?.id == m.id) {
          setState(() {
            _replyTo = null;
            if (_editing != null) _input.clear();
            _editing = null;
          });
        }
        // let the dialog fade out first so the dust is visible
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return;
        await _dissolve(m.id, () => _app!.deleteMessage(chat, m));
      case MsgAction.copy:
        break;
    }
  }

  /// Scrolls to a message (older ones are further up), then makes it glow.
  Future<void> _jumpTo(String id) async {
    for (var n = 0; n < 60 && mounted && _listCtl.hasClients; n++) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, alignment: 0.45, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
        if (!mounted) return;
        _flash.value = id;
        Timer(const Duration(milliseconds: 1300), () {
          if (mounted && _flash.value == id) _flash.value = null;
        });
        return;
      }
      final pos = _listCtl.position;
      if (pos.pixels >= pos.maxScrollExtent - 1) {
        await WidgetsBinding.instance.endOfFrame;
        if (_listCtl.position.pixels >= _listCtl.position.maxScrollExtent - 1 && _keys[id]?.currentContext == null) return;
        continue;
      }
      pos.jumpTo(math.min(pos.pixels + pos.viewportDimension * 0.8, pos.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Plays the dust animation, then drops the bubble from the list.
  Future<void> _dissolve(String id, [Future<void> Function()? alongside]) async {
    setState(() => _dissolving.add(id));
    final anim = _keys[id]?.currentState?.dissolve();
    if (alongside != null) unawaited(alongside());
    await anim;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    setState(() {
      _dissolving.remove(id);
      _gone.add(id);
    });
  }

  Future<Chat?> _pickChat() => showModalBottomSheet<Chat>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final app = AppScope.of(ctx);
      return ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: Text(ctx.tr('forward_to'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            ),
            ListTile(
              leading: const SavedAvatar(size: 44),
              title: Text(ctx.tr('saved_messages'), style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                final saved = await app.savedChat();
                if (ctx.mounted) Navigator.pop(ctx, saved);
              },
            ),
            for (final c in app.chats)
              if (!c.isSaved)
                ListTile(
                  leading: ChatAvatar(chat: c, size: 44),
                  title: Text(app.chatTitle(c), style: const TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () => Navigator.pop(ctx, c),
                ),
          ],
        ),
      );
    },
  );

  void _openInfo(AppController app, Chat chat) {
    if (chat.isSaved) return;
    final peer = chat.isGroup ? null : chat.peer(app.myId ?? '');
    if (!chat.isGroup && peer == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => chat.isGroup ? ProfileScreen.group(chatId: chat.id) : ProfileScreen.user(profile: peer!, chatId: chat.id),
      ),
    );
  }

  Future<void> _call(Chat chat, bool video) async {
    final err = await CallScope.read(context).call(chat, withVideo: video);
    if (err != null) _toast(err);
  }

  Future<void> _addMember(Chat chat) async {
    final p = await showDialog<Profile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('add_member')),
        content: SizedBox(
          width: 420,
          child: PersonFinder(buttonKey: 'add', onFound: (p) => Navigator.pop(ctx, p)),
        ),
      ),
    );
    if (p == null || !mounted) return;
    await _app!.addMember(chat, p);
    _toast('added');
  }

  Future<void> _openUser(String uid) async {
    final c = await _app!.openDirect(uid);
    if (c == null) return _toast('err_generic');
    if (!mounted || c.id == widget.chatId) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: c.id)));
  }

  String _subtitle(AppController app, Chat c) {
    if (c.isGroup) return '${context.digits(c.members.length)} ${context.tr('members')}';
    final p = c.peer(app.myId ?? '');
    if (p == null) return '';
    return p.username != null ? '@${p.username}' : p.email;
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final chat = app.chatById(widget.chatId);
    if (chat == null) return const Scaffold(body: SizedBox.shrink());
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureBottom());
    final cs = Theme.of(context).colorScheme;
    final title = app.chatTitle(chat);
    final msgs = app.messagesOf(chat.id);
    final pinned = chat.pinnedMessageId == null ? null : app.messageById(chat.id, chat.pinnedMessageId!);
    final barTop = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final pageColor = dark(context) ? Brand.nightChatBg : Brand.lightChatBg;

    return PopScope(
      canPop: !_emoji,
      onPopInvokedWithResult: (did, _) {
        if (!did && _emoji) setState(() => _emoji = false);
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          automaticallyImplyLeading: !widget.embedded,
          // No colour of its own: the bar sits on the page's soft top edge.
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleSpacing: widget.embedded ? 16 : 0,
          title: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openInfo(app, chat),
            child: Row(
              children: [
                ChatAvatar(chat: chat, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                      if (!chat.isSaved)
                        Text(
                          _subtitle(app, chat),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (!chat.isGroup && !chat.isSaved) ...[
              IconButton(tooltip: context.tr('video_call'), onPressed: () => _call(chat, true), icon: const Icon(Icons.videocam_rounded)),
              IconButton(tooltip: context.tr('voice_call'), onPressed: () => _call(chat, false), icon: const Icon(Icons.call_rounded)),
            ],
            PopupMenuButton<String>(
              onOpened: () => FocusManager.instance.primaryFocus?.unfocus(),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) async {
                switch (v) {
                  case 'info':
                    _openInfo(app, chat);
                  case 'add':
                    _addMember(chat);
                  case 'mute':
                    await app.toggleMute(chat);
                    _toast(chat.muted ? 'muted_toast' : 'unmuted_toast');
                  case 'clear':
                    await clearHistoryFlow(context, chat);
                  case 'leave':
                    final nav = Navigator.of(context);
                    if (await deleteChatFlow(context, chat) && !widget.embedded) nav.pop();
                }
              },
              itemBuilder: (ctx) => [
                if (!chat.isSaved) _menuItem(ctx, 'info', Icons.info_rounded, 'info'),
                if (chat.isGroup) _menuItem(ctx, 'add', Icons.person_add_alt_1_rounded, 'add_member'),
                if (!chat.isSaved)
                  _menuItem(
                    ctx,
                    'mute',
                    chat.muted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                    chat.muted ? 'unmute_chat' : 'mute_chat',
                  ),
                _menuItem(ctx, 'clear', Icons.cleaning_services_rounded, 'clear_history'),
                if (!chat.isSaved)
                  _menuItem(
                    ctx,
                    'leave',
                    chat.isGroup ? Icons.logout_rounded : Icons.delete_rounded,
                    chat.isGroup ? 'leave_chat' : 'delete_chat',
                    danger: true,
                  ),
              ],
            ),
          ],
        ),
        body: GirihWallpaper(
          child: Stack(
            children: [
              // Messages run under the header and under the input bar.
              Positioned.fill(
                child: msgs == null ? const Center(child: CircularProgressIndicator()) : _list(app, chat, msgs, barTop + (pinned != null ? 52 : 0) + 8),
              ),
              // Soft top edge: messages fade out gradually under the header.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: barTop + (pinned != null ? 52 : 0) + 44,
                child: RepaintBoundary(
                  child: SoftEdge(fromTop: true, color: pageColor, blur: false, solid: barTop + (pinned != null ? 52 : 0)),
                ),
              ),
              if (pinned != null) Positioned(top: barTop, left: 0, right: 0, child: _pinnedBar(app, chat, pinned)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: KeyedSubtree(
                  key: _bottomKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: LayoutBuilder(
                                builder: (_, c) => SoftEdge(fromTop: false, color: pageColor, blur: false, solid: (c.maxHeight - 34).clamp(0.0, 400.0)),
                              ),
                            ),
                          ),
                          Padding(padding: const EdgeInsets.only(top: 34), child: _composer(chat)),
                        ],
                      ),
                      if (_emoji) _emojiPanel(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool dark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

  PopupMenuItem<String> _menuItem(BuildContext ctx, String v, IconData icon, String key, {bool danger = false}) => PopupMenuItem(
    value: v,
    child: Row(
      children: [
        Icon(icon, size: 21, color: danger ? Brand.pomegranate : Theme.of(ctx).colorScheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Text(ctx.tr(key), style: TextStyle(color: danger ? Brand.pomegranate : null)),
      ],
    ),
  );

  Widget _list(AppController app, Chat chat, List<Message> all, double topPad) {
    final s = Strings(context.lang);
    // Messages deleted before we saw them are simply left out; ones deleted
    // while on screen (by anyone) turn to dust first.
    final visible = <Message>[];
    for (final m in all) {
      if (m.deleted && !_dissolving.contains(m.id)) {
        if (_gone.contains(m.id) || !_shown.contains(m.id)) continue;
        WidgetsBinding.instance.addPostFrameCallback((_) => _dissolve(m.id));
        _dissolving.add(m.id);
      }
      visible.add(m);
    }
    if (visible.isEmpty) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(22)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(chat.isSaved ? Icons.bookmark_rounded : Icons.waving_hand_rounded, size: 52, color: Colors.white),
              const SizedBox(height: 10),
              Text(
                context.tr(chat.isSaved ? 'saved_messages' : 'no_messages'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                context.tr(chat.isSaved ? 'saved_hint' : 'say_hello'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    bool joined(Message a, Message b) =>
        a.senderId == b.senderId && sameDay(a.createdAt, b.createdAt) && b.createdAt.difference(a.createdAt).inMinutes.abs() < 5;

    // Only light data here; the bubbles themselves are built lazily,
    // just for the rows that are on screen.
    final entries = <Object>[]; // String = day header, (Message, GroupPos, bool) = message
    for (var i = 0; i < visible.length; i++) {
      final m = visible[i];
      final prev = i > 0 ? visible[i - 1] : null;
      final next = i < visible.length - 1 ? visible[i + 1] : null;
      final newDay = prev == null || !sameDay(prev.createdAt, m.createdAt);
      if (newDay) entries.add(dayHeader(m.createdAt, context.lang, s));
      final jp = !newDay && joined(prev, m);
      final jn = next != null && joined(m, next);
      final pos = jp && jn ? GroupPos.middle : (jp ? GroupPos.last : (jn ? GroupPos.first : GroupPos.single));
      _shown.add(m.id);
      entries.add((m, pos, jp));
    }
    Widget build(int i) {
      final e = entries[entries.length - 1 - i];
      if (e is String) return SystemChip(text: e);
      final (m, pos, jp) = e as (Message, GroupPos, bool);
      final bubble = Dissolvable(
        key: _keys.putIfAbsent(m.id, () => GlobalKey<DissolvableState>()),
        child: MessageBubble(
          key: ValueKey(m.id),
          chat: chat,
          message: m,
          pos: pos,
          senderName: chat.isGroup && !jp ? (app.memberById(chat, m.senderId)?.name ?? '') : null,
          onReply: m.deleted ? null : (msg) => _onAction(chat, msg, MsgAction.reply),
          onAction: (msg, a) => _onAction(chat, msg, a),
          onOpenUser: _openUser,
          onJump: _jumpTo,
          onShowAll: chat.isSaved ? null : () => _openInfo(app, chat),
        ),
      );
      return ValueListenableBuilder<String?>(
        valueListenable: _flash,
        child: bubble,
        builder: (_, f, child) => AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          color: f == m.id ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18) : Colors.transparent,
          child: child,
        ),
      );
    }

    return ListView.builder(
      controller: _listCtl,
      reverse: true,
      // each bubble already has its own repaint boundary (Dissolvable)
      addRepaintBoundaries: false,
      addAutomaticKeepAlives: false,
      // build a bit beyond the screen, so fast flings don't build mid-frame
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(8, topPad, 8, _bottomH + 4),
      itemCount: entries.length,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        for (var i = 0; i < entries.length; i++) {
          final e = entries[entries.length - 1 - i];
          if (e is (Message, GroupPos, bool) && 'msg-${e.$1.id}' == key.value) return i;
        }
        return null;
      },
      itemBuilder: (_, i) => KeyedSubtree(key: ValueKey(_entryKey(entries[entries.length - 1 - i])), child: build(i)),
    );
  }

  String _entryKey(Object e) => e is String ? 'day-$e' : 'msg-${(e as (Message, GroupPos, bool)).$1.id}';

  Widget _pinnedBar(AppController app, Chat chat, Message pinned) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _jumpTo(pinned.id),
        child: Container(
          height: 52,
          padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 34,
                decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('pinned_message'),
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    Text(app.previewOf(pinned).replaceAll('\n', ' '), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                  ],
                ),
              ),
              IconButton(
                tooltip: context.tr('unpin'),
                onPressed: () => app.pinMessage(chat, null),
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emojiPanel() {
    final cs = Theme.of(context).colorScheme;
    final bg = dark(context) ? Brand.nightSurface : Colors.white;
    final safe = MediaQuery.paddingOf(context).bottom;
    return Container(
      height: _emojiHeight + safe,
      color: bg,
      padding: EdgeInsets.only(bottom: safe),
      child: EmojiPicker(
        textEditingController: _input,
        onEmojiSelected: (_, _) => setState(() => _canSend = _input.text.trim().isNotEmpty),
        onBackspacePressed: () => setState(() => _canSend = _input.text.trim().isNotEmpty),
        config: Config(
          height: _emojiHeight,
          checkPlatformCompatibility: true,
          locale: Locale(context.lang.code),
          viewOrderConfig: const ViewOrderConfig(top: EmojiPickerItem.categoryBar, middle: EmojiPickerItem.emojiView, bottom: EmojiPickerItem.searchBar),
          emojiViewConfig: EmojiViewConfig(
            columns: 8,
            emojiSizeMax: 28 * (defaultTargetPlatform == TargetPlatform.iOS ? 1.2 : 1.0),
            backgroundColor: bg,
            buttonMode: ButtonMode.MATERIAL,
            recentsLimit: 32,
            noRecents: Text(context.tr('no_recent_emoji'), style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant)),
          ),
          categoryViewConfig: CategoryViewConfig(
            initCategory: Category.SMILEYS,
            backgroundColor: bg,
            indicatorColor: cs.primary,
            iconColor: cs.onSurfaceVariant.withValues(alpha: 0.7),
            iconColorSelected: cs.primary,
            backspaceColor: cs.primary,
            dividerColor: cs.outlineVariant,
          ),
          bottomActionBarConfig: BottomActionBarConfig(backgroundColor: bg, buttonColor: bg, buttonIconColor: cs.onSurfaceVariant),
          searchViewConfig: SearchViewConfig(backgroundColor: bg, buttonIconColor: cs.onSurfaceVariant, hintText: context.tr('search')),
          skinToneConfig: SkinToneConfig(dialogBackgroundColor: bg, indicatorColor: cs.primary),
        ),
      ),
    );
  }

  Widget _composer(Chat chat) {
    final cs = Theme.of(context).colorScheme;
    final app = AppScope.of(context);
    final field = dark(context) ? Brand.nightRaised : Colors.white;
    return SafeArea(
      top: false,
      bottom: !_emoji,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: (_replyTo != null || _editing != null) ? _contextBar(app, chat) : const SizedBox(width: double.infinity),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    decoration: BoxDecoration(
                      color: field,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 1))],
                    ),
                    child: _recording ? _recordingStrip(chat) : _textRow(chat, cs),
                  ),
                ),
                const SizedBox(width: 6),
                _actionButton(chat, cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _textRow(Chat chat, ColorScheme cs) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      IconButton(
        tooltip: context.tr(_emoji ? 'keyboard' : 'emoji'),
        onPressed: () {
          setState(() => _emoji = !_emoji);
          if (_emoji) {
            _focus.unfocus();
            SystemChannels.textInput.invokeMethod('TextInput.hide');
          } else {
            _focus.requestFocus();
          }
        },
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (c, a) => RotationTransition(
            turns: Tween(begin: 0.75, end: 1.0).animate(a),
            child: FadeTransition(opacity: a, child: c),
          ),
          child: Icon(_emoji ? Icons.keyboard_rounded : Icons.emoji_emotions_rounded, key: ValueKey(_emoji), color: cs.onSurfaceVariant),
        ),
      ),
      Expanded(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.enter): () => _send(chat),
            const SingleActivator(LogicalKeyboardKey.numpadEnter): () => _send(chat),
          },
          child: TextField(
            controller: _input,
            focusNode: _focus,
            minLines: 1,
            maxLines: 6,
            maxLength: 4000,
            onTap: () {
              if (_emoji) setState(() => _emoji = false);
            },
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(fontSize: 16.5),
            onChanged: (v) {
              final can = v.trim().isNotEmpty;
              if (can != _canSend) setState(() => _canSend = can);
            },
            decoration: InputDecoration(
              hintText: context.tr('type_message'),
              counterText: '',
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: _canSend || _editing != null
            ? const SizedBox(width: 10, key: ValueKey('gap'))
            : IconButton(
                key: const ValueKey('attach'),
                tooltip: context.tr('attach'),
                onPressed: () => _attachMenu(chat),
                icon: Transform.rotate(angle: 0.6, child: Icon(Icons.attach_file_rounded, color: cs.onSurfaceVariant)),
              ),
      ),
    ],
  );

  Widget _recordingStrip(Chat chat) {
    final cs = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final d = DateTime.now().difference(_recStart ?? DateTime.now());
    final t = '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')},${d.inMilliseconds % 1000 ~/ 100}';
    final blink = d.inMilliseconds % 1000 < 500;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const SizedBox(width: 16),
          AnimatedOpacity(
            opacity: blink ? 1 : 0.15,
            duration: const Duration(milliseconds: 250),
            child: const Icon(Icons.circle, size: 11, color: Brand.pomegranate),
          ),
          const SizedBox(width: 8),
          Text(
            context.digits(t),
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
          ),
          Expanded(
            child: Center(
              child: _locked
                  ? TextButton(
                      onPressed: () => _stopRecording(chat, send: false),
                      child: Text(
                        context.tr('cancel'),
                        style: const TextStyle(color: Brand.pomegranate, fontWeight: FontWeight.w800),
                      ),
                    )
                  : Opacity(
                      opacity: (1 - _slideX / 130).clamp(0.15, 1.0),
                      child: Transform.translate(
                        offset: Offset((rtl ? 1 : -1) * _slideX * 0.7, 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // chevron_left mirrors itself in RTL, so it always points toward "cancel".
                            Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
                            Text(
                              context.tr('slide_cancel'),
                              style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(Chat chat, ColorScheme cs) {
    final sendMode = _canSend || _locked || _editing != null;
    final icon = _locked ? Icons.send_rounded : (_editing != null ? Icons.check_rounded : (sendMode ? Icons.send_rounded : Icons.mic_rounded));
    final button = AnimatedScale(
      scale: _recording && !_locked ? 1.5 : 1,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: Icon(icon, key: ValueKey(icon), color: Colors.white),
        ),
      ),
    );
    if (sendMode) {
      return Semantics(
        button: true,
        label: context.tr(_editing != null ? 'save' : 'send'),
        excludeSemantics: true,
        onTap: () => _locked ? _stopRecording(chat, send: true) : _send(chat),
        child: GestureDetector(onTap: () => _locked ? _stopRecording(chat, send: true) : _send(chat), child: button),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        // The lock target rises above the mic while holding.
        if (_recording && !_locked)
          Positioned(
            bottom: 70 + _slideY * 0.35,
            child: Container(
              width: 40,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: dark(context) ? Brand.nightRaised : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 8)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_slideY > 55 ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20, color: cs.onSurfaceVariant),
                  Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
        Semantics(
          button: true,
          label: context.tr('voice_message'),
          excludeSemantics: true,
          onTap: () => _toast('hold_to_record'),
          onLongPress: _recording ? null : _startRecording,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _micDown,
            onPointerMove: (e) => _micMove(e, chat),
            onPointerUp: (_) => _micUp(chat, cancelled: false),
            onPointerCancel: (_) => _micUp(chat, cancelled: true),
            // a slightly bigger touch area than the round button
            child: Padding(padding: const EdgeInsets.all(4), child: button),
          ),
        ),
      ],
    );
  }

  Widget _contextBar(AppController app, Chat chat) {
    final cs = Theme.of(context).colorScheme;
    final m = _editing ?? _replyTo!;
    final editing = _editing != null;
    final who = editing ? context.tr('edit_message') : (m.senderId == app.myId ? context.tr('you') : (app.memberById(chat, m.senderId)?.name ?? ''));
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 2, 6),
      decoration: BoxDecoration(
        color: dark(context) ? Brand.nightRaised : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 6, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          Icon(editing ? Icons.edit_rounded : Icons.reply_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Container(
            width: 2.5,
            height: 34,
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  who,
                  maxLines: 1,
                  style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                ),
                Text(app.previewOf(m).replaceAll('\n', ' '), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('cancel'),
            onPressed: () => setState(() {
              if (editing) _input.clear();
              _editing = null;
              _replyTo = null;
              _canSend = _input.text.trim().isNotEmpty;
            }),
            icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
