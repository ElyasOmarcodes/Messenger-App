import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

enum RelayState { offline, connecting, online }

/// One event delivered by the relay.
class RelayEvent {
  RelayEvent({required this.id, required this.topic, required this.time, required this.body});
  final String id;
  final String topic;
  final int time; // unix seconds
  final String body;
}

/// Transport layer.
///
/// Prototype: uses the free public ntfy.sh pub/sub service (open source,
/// Apache-2.0/GPLv2). Publishing is a plain HTTP POST; receiving is one
/// WebSocket that carries every topic we listen to. ntfy keeps messages for
/// ~12 hours, so a phone that was offline still gets what it missed.
///
/// Later: run our own ntfy (or a custom server) and only change [baseUrl].
class Relay {
  Relay({required this.baseUrl, required this.onEvent, required this.onState});

  String baseUrl;
  final void Function(RelayEvent e) onEvent;
  final void Function(RelayState s) onState;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  List<String> _topics = const [];
  int Function()? _since;
  bool _closed = false;
  RelayState state = RelayState.offline;

  void _set(RelayState s) {
    state = s;
    onState(s);
  }

  /// Opens (or re-opens) the subscription. [since] returns the unix time of the
  /// last event we stored, so reconnects only fetch what we missed.
  void connect(List<String> topics, int Function() since, {bool force = false}) {
    final next = topics.toSet().toList()..sort();
    _since = since;
    // Every (re)connect counts against the relay's rate limit, so skip it
    // when we are already listening to exactly these topics.
    final same = next.join(',') == _topics.join(',');
    if (same && !force && !_closed && state != RelayState.offline) return;
    _topics = next;
    _closed = false;
    _open();
  }

  Future<void> _open() async {
    await _teardown();
    if (_closed || _topics.isEmpty) return;
    _set(RelayState.connecting);
    final s = _since?.call() ?? 0;
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
      scheme: base.scheme == 'http' ? 'ws' : 'wss',
      path: '${base.path.replaceAll(RegExp(r'/$'), '')}/${_topics.join(',')}/ws',
      queryParameters: {'since': s > 0 ? '$s' : 'all'},
    );
    try {
      final ch = WebSocketChannel.connect(uri);
      _channel = ch;
      await ch.ready.timeout(const Duration(seconds: 15));
      _attempt = 0;
      _set(RelayState.online);
      _sub = ch.stream.listen(
        _handle,
        onError: (_) => _scheduleRetry(),
        onDone: _scheduleRetry,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _handle(dynamic raw) {
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      if (j['event'] != 'message') return;
      onEvent(RelayEvent(
        id: j['id'] as String,
        topic: j['topic'] as String,
        time: (j['time'] as num).toInt(),
        body: (j['message'] as String?) ?? '',
      ));
    } catch (_) {
      // Ignore anything that is not ours.
    }
  }

  void _scheduleRetry() {
    if (_closed) return;
    _set(RelayState.offline);
    _retry?.cancel();
    final secs = [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)];
    _attempt++;
    _retry = Timer(Duration(seconds: secs), _open);
  }

  Future<void> _teardown() async {
    _retry?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> close() async {
    _closed = true;
    await _teardown();
    _set(RelayState.offline);
  }

  /// Returns true when the relay accepted the message. Retries briefly when
  /// the relay is busy (HTTP 429/5xx) or the network drops.
  Future<bool> publish(String topic, String body) async {
    final uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/$'), '')}/$topic');
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) await Future<void>.delayed(Duration(seconds: attempt * 3));
      try {
        final res = await http.post(uri, body: body).timeout(const Duration(seconds: 15));
        if (res.statusCode >= 200 && res.statusCode < 300) return true;
        if (res.statusCode != 429 && res.statusCode < 500) return false;
      } catch (_) {
        // network error: try again
      }
    }
    return false;
  }
}
