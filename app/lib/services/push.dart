import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'notifier.dart';

/// Push notifications through Firebase Cloud Messaging (Android) and APNs
/// via FCM (iPhone): messages and calls reach the phone even when the app is
/// closed. The push never carries message text (end-to-end encryption): the
/// phone shows who wrote; the message itself is fetched when the app opens.
class Push {
  Push._();

  static FirebaseOptions? get _options {
    if (AppConfig.fcmProjectId.isEmpty || AppConfig.fcmApiKey.isEmpty || kIsWeb) return null;
    final appId = defaultTargetPlatform == TargetPlatform.iOS ? AppConfig.fcmIosAppId : AppConfig.fcmAndroidAppId;
    if (appId.isEmpty) return null;
    return FirebaseOptions(apiKey: AppConfig.fcmApiKey, appId: appId, messagingSenderId: AppConfig.fcmSenderId, projectId: AppConfig.fcmProjectId);
  }

  static bool get configured => _options != null;
  static bool _started = false;
  static String? _token;

  /// Call once at startup (before runApp is fine).
  static Future<void> init() async {
    final o = _options;
    if (o == null) return;
    try {
      await Firebase.initializeApp(options: o);
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);
    } catch (_) {}
  }

  /// After sign-in: ask permission, register this phone, listen.
  static Future<void> start({
    required String lang,
    required void Function() onMessage,
    required void Function() onCall,
    required void Function(String chatId) onOpenChat,
  }) async {
    if (!configured || _started) return;
    _started = true;
    try {
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();
      await fm.setForegroundNotificationPresentationOptions(alert: false, badge: true, sound: false);
      // the token arrives (and later changes) through onRegistered
      fm.onRegistered.listen((t) {
        _token = t;
        unawaited(_save(t, lang));
      });
      await fm.register();
      // app open: the live connection usually has it already; this catches
      // what it missed (and never shows a second notification)
      FirebaseMessaging.onMessage.listen((m) => m.data['type'] == 'call' ? onCall() : onMessage());
      void opened(RemoteMessage m) {
        if (m.data['type'] == 'call') return onCall();
        final c = m.data['chat_id'];
        if (c is String) onOpenChat(c);
      }

      FirebaseMessaging.onMessageOpenedApp.listen(opened);
      final first = await fm.getInitialMessage();
      if (first != null) opened(first);
    } catch (_) {}
  }

  static Future<void> _save(String token, String lang) async {
    final sb = Supabase.instance.client;
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await sb.from('push_tokens').upsert({
        'token': token,
        'user_id': uid,
        'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'lang': lang,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Signing out: this phone stops getting that account's pushes.
  static Future<void> stop() async {
    final t = _token;
    _started = false;
    if (t == null) return;
    try {
      await Supabase.instance.client.from('push_tokens').delete().eq('token', t);
      await FirebaseMessaging.instance.unregister();
    } catch (_) {}
    _token = null;
  }
}

/// Runs in a background isolate when a push arrives and the app is not in
/// front (also when it was closed). Android pushes are data-only, so the app
/// shows the notification itself: a message, or a full-screen ringing call.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage m) async {
  WidgetsFlutterBinding.ensureInitialized();
  final d = m.data;
  if (defaultTargetPlatform == TargetPlatform.iOS) return; // APNs shows the alert itself
  await Notifier.instance.init(askPermission: false);
  final chat = d['chat_id'] as String? ?? '';
  if (d['type'] == 'call') {
    await Notifier.instance.show(
      id: (d['call_id'] as String? ?? chat).hashCode & 0x7fffffff,
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      payload: 'call:${d['call_id']}',
      call: true,
    );
  } else {
    await Notifier.instance.show(id: chat.hashCode & 0x7fffffff, title: d['title'] as String? ?? '', body: d['body'] as String? ?? '', payload: 'chat:$chat');
  }
}
