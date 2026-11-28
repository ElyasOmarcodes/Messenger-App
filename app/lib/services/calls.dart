import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models/models.dart';
import 'messenger.dart';
import 'notifier.dart';

enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

/// One-to-one voice/video calls.
///
/// Media flows directly between the two devices (WebRTC). The server only
/// carries the call invitation and the connection details ("signalling"),
/// through the `calls` and `call_signals` tables, so only the two people in
/// the call can see them (Row Level Security).
class CallController extends ChangeNotifier {
  CallController(this.app);
  final AppController app;

  SupabaseClient get _sb => Supabase.instance.client;

  CallPhase phase = CallPhase.idle;
  String? callId;
  String? chatId;
  bool video = false;
  bool outgoing = false;
  Profile? peer;
  DateTime? startedAt;
  String? endReason; // declined | missed | ended | failed | busy

  bool muted = false;
  bool cameraOff = false;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  RealtimeChannel? _callsChannel;
  RealtimeChannel? _signalChannel;
  final Set<int> _seenSignals = {};
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteSet = false;
  Timer? _ringTimer;

  bool get busy => phase != CallPhase.idle && phase != CallPhase.ended;

  // TURN relay: short-lived credentials from the "turn" Edge Function
  // (coturn, REST auth). Needed behind carrier NAT (CGNAT), where most
  // mobile calls cannot connect directly.
  Map<String, dynamic>? _turn;
  DateTime _turnUntil = DateTime(0);

  Future<Map<String, dynamic>> _iceConfig() async {
    if (_turn == null || DateTime.now().isAfter(_turnUntil)) {
      try {
        final r = await _sb.functions.invoke('turn').timeout(const Duration(seconds: 6));
        final d = Map<String, dynamic>.from(r.data as Map);
        if ((d['urls'] as List).isNotEmpty) {
          _turn = {'urls': d['urls'], 'username': d['username'], 'credential': d['credential']};
          _turnUntil = DateTime.now().add(Duration(seconds: ((d['ttl'] as num?) ?? 3600).toInt() - 300));
        }
      } catch (_) {
        // no TURN function deployed (or offline): direct + STUN only
      }
    }
    return {
      'iceServers': [
        {
          'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'],
        },
        ?_turn,
        if (AppConfig.turnUrl.isNotEmpty) {'urls': AppConfig.turnUrl, 'username': AppConfig.turnUser, 'credential': AppConfig.turnPass},
      ],
    };
  }

  // ── Listening for incoming calls ─────────────────────────────────────────
  void start() {
    final me = app.myId;
    if (me == null || _callsChannel != null) return;
    _callsChannel = _sb
        .channel('calls-$me')
        .onPostgresChanges(event: PostgresChangeEvent.insert, schema: 'public', table: 'calls', callback: (p) => _onCallInsert(p.newRecord))
        .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'calls', callback: (p) => _onCallUpdate(p.newRecord))
        .subscribe();
    unawaited(checkRinging());
  }

  /// Opened from a call notification (push) — or the app was asleep when
  /// the call came: pick up a call that is still ringing for me.
  Future<void> checkRinging() async {
    final me = app.myId;
    if (me == null || busy) return;
    try {
      final since = DateTime.now().toUtc().subtract(const Duration(seconds: 45)).toIso8601String();
      final rows = await _sb
          .from('calls')
          .select()
          .eq('callee_id', me)
          .eq('status', 'ringing')
          .gt('created_at', since)
          .order('created_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty && !busy) _onCallInsert(rows.first);
    } catch (_) {}
  }

  void stop() {
    _callsChannel?.unsubscribe();
    _callsChannel = null;
    _cleanup();
    phase = CallPhase.idle;
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  void _onCallInsert(Map<String, dynamic> row) {
    if (row['callee_id'] != app.myId || row['status'] != 'ringing') return;
    final created = DateTime.parse(row['created_at'] as String);
    if (DateTime.now().toUtc().difference(created).inSeconds > 45) return; // stale
    final id = row['id'] as String;
    if (busy) {
      _sb.from('calls').update({'status': 'declined'}).eq('id', id);
      return;
    }
    final chat = app.chatById(row['chat_id'] as String);
    callId = id;
    chatId = row['chat_id'] as String;
    video = row['video'] as bool;
    outgoing = false;
    peer = chat == null ? null : app.memberById(chat, row['caller_id'] as String);
    endReason = null;
    phase = CallPhase.incoming;
    notifyListeners();
    Notifier.instance.show(
      id: 7,
      title: peer?.name ?? 'Paigham',
      body: app.s.get(video ? 'incoming_video' : 'incoming_voice'),
      payload: 'call:$id',
      call: true,
    );
    _ringTimer?.cancel();
    _ringTimer = Timer(const Duration(seconds: 45), () {
      if (phase == CallPhase.incoming && callId == id) _finish('missed');
    });
  }

  void _onCallUpdate(Map<String, dynamic> row) {
    if (row['id'] != callId) return;
    final st = row['status'] as String;
    if (st == 'accepted' && outgoing && phase == CallPhase.outgoing) {
      phase = CallPhase.connecting;
      _ringTimer?.cancel();
      notifyListeners();
    } else if (st == 'declined' || st == 'ended' || st == 'missed') {
      _finish(st, remote: true);
    }
  }

  // ── Outgoing ─────────────────────────────────────────────────────────────
  /// Returns a translation key on failure.
  Future<String?> call(Chat chat, {required bool withVideo}) async {
    if (busy) return 'call_busy';
    final other = chat.peer(app.myId ?? '');
    if (other == null) return 'err_generic';
    peer = other;
    chatId = chat.id;
    video = withVideo;
    outgoing = true;
    endReason = null;
    phase = CallPhase.outgoing;
    notifyListeners();
    try {
      await _ensureRenderers();
      await _openMedia();
      final row = await _sb.from('calls').insert({'chat_id': chat.id, 'caller_id': app.myId, 'callee_id': other.id, 'video': withVideo}).select().single();
      callId = row['id'] as String;
      await _createPeer();
      _listenSignals();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': withVideo});
      await _pc!.setLocalDescription(offer);
      await _signal('offer', {'sdp': offer.sdp, 'type': offer.type});
      _ringTimer?.cancel();
      _ringTimer = Timer(const Duration(seconds: 45), () {
        if (phase == CallPhase.outgoing) hangUp(reason: 'missed');
      });
      return null;
    } catch (e) {
      debugPrint('call failed: $e');
      _finish('failed');
      return 'call_failed';
    }
  }

  // ── Incoming ─────────────────────────────────────────────────────────────
  Future<void> accept() async {
    if (phase != CallPhase.incoming || callId == null) return;
    _ringTimer?.cancel();
    Notifier.instance.cancel(7);
    phase = CallPhase.connecting;
    notifyListeners();
    try {
      await _ensureRenderers();
      await _openMedia();
      await _createPeer();
      await _sb.from('calls').update({'status': 'accepted', 'answered_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId!);
      // The offer (and early ICE) were written before we joined: read them first.
      final rows = await _sb.from('call_signals').select().eq('call_id', callId!).order('id');
      for (final r in rows) {
        await _onSignal(r);
      }
      _listenSignals();
    } catch (e) {
      debugPrint('accept failed: $e');
      hangUp(reason: 'failed');
    }
  }

  Future<void> decline() async {
    if (callId == null) return;
    Notifier.instance.cancel(7);
    await _sb.from('calls').update({'status': 'declined', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', callId!);
    _finish('declined');
  }

  Future<void> hangUp({String reason = 'ended'}) async {
    final id = callId;
    _finish(reason);
    if (id != null) {
      try {
        await _sb.from('calls').update({'status': reason == 'missed' ? 'missed' : 'ended', 'ended_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id);
      } catch (_) {}
    }
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  void toggleCamera() {
    cameraOff = !cameraOff;
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !cameraOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final t = _local?.getVideoTracks();
    if (t != null && t.isNotEmpty) await Helper.switchCamera(t.first);
  }

  /// Called by the UI after showing the "call ended" state for a moment.
  void reset() {
    if (phase == CallPhase.ended) {
      phase = CallPhase.idle;
      notifyListeners();
    }
  }

  // ── WebRTC plumbing ──────────────────────────────────────────────────────
  Future<void> _openMedia() async {
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      // data saver: a smaller picture uses much less of a weak connection
      'video': video
          ? {'facingMode': 'user', 'width': app.dataSaver ? 320 : 640, 'height': app.dataSaver ? 240 : 480, 'frameRate': app.dataSaver ? 15 : 24}
          : false,
    });
    localRenderer.srcObject = _local;
    muted = false;
    cameraOff = false;
  }

  Future<void> _createPeer() async {
    _remoteSet = false;
    _pendingIce.clear();
    _seenSignals.clear();
    final pc = await createPeerConnection(await _iceConfig());
    _pc = pc;
    for (final t in _local!.getTracks()) {
      await pc.addTrack(t, _local!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _signal('ice', {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex});
    };
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams.first;
        notifyListeners();
      }
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        phase = CallPhase.active;
        startedAt = DateTime.now();
        notifyListeners();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        hangUp(reason: 'failed');
      }
    };
  }

  void _listenSignals() {
    _signalChannel?.unsubscribe();
    _signalChannel = _sb
        .channel('signals-$callId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'call_signals',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'call_id', value: callId!),
          callback: (p) => _onSignal(p.newRecord),
        )
        .subscribe();
  }

  Future<void> _signal(String kind, Map<String, dynamic> payload) async {
    if (callId == null) return;
    try {
      await _sb.from('call_signals').insert({'call_id': callId, 'sender_id': app.myId, 'kind': kind, 'payload': payload});
    } catch (_) {}
  }

  Future<void> _onSignal(Map<String, dynamic> r) async {
    final id = (r['id'] as num).toInt();
    if (r['sender_id'] == app.myId || !_seenSignals.add(id) || _pc == null) return;
    final p = r['payload'] as Map<String, dynamic>;
    switch (r['kind']) {
      case 'offer':
        await _pc!.setRemoteDescription(RTCSessionDescription(p['sdp'] as String?, p['type'] as String?));
        await _flushIce();
        final answer = await _pc!.createAnswer();
        await _pc!.setLocalDescription(answer);
        await _signal('answer', {'sdp': answer.sdp, 'type': answer.type});
      case 'answer':
        await _pc!.setRemoteDescription(RTCSessionDescription(p['sdp'] as String?, p['type'] as String?));
        await _flushIce();
      case 'ice':
        final c = RTCIceCandidate(p['candidate'] as String?, p['sdpMid'] as String?, (p['sdpMLineIndex'] as num?)?.toInt());
        if (_remoteSet) {
          await _pc!.addCandidate(c);
        } else {
          _pendingIce.add(c);
        }
    }
  }

  Future<void> _flushIce() async {
    _remoteSet = true;
    for (final c in _pendingIce) {
      await _pc!.addCandidate(c);
    }
    _pendingIce.clear();
  }

  void _finish(String reason, {bool remote = false}) {
    if (phase == CallPhase.idle || phase == CallPhase.ended) return;
    _ringTimer?.cancel();
    Notifier.instance.cancel(7);
    endReason = reason;
    phase = CallPhase.ended;
    _cleanup();
    notifyListeners();
  }

  void _cleanup() {
    _signalChannel?.unsubscribe();
    _signalChannel = null;
    try {
      _local?.getTracks().forEach((t) => t.stop());
      _local?.dispose();
    } catch (_) {}
    _local = null;
    try {
      _pc?.close();
    } catch (_) {}
    _pc = null;
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    startedAt = null;
  }

  Future<List<CallRecord>> history() async {
    try {
      final data = await _sb.rpc('my_calls') as List<dynamic>;
      return data.map((e) => CallRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
