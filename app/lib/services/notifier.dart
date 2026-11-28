import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// System notifications for new messages and incoming calls while the app
/// is running (foreground or background).
///
/// Delivery to a fully closed app needs a push service (Firebase Cloud
/// Messaging on Android, APNs on iPhone); see docs/ARCHITECTURE.md.
class Notifier {
  Notifier._();
  static final instance = Notifier._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String payload)? onTap;

  Future<void> init({bool askPermission = true}) async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(appName: 'Paigham', appUserModelId: 'Paigham.Messenger', guid: '6d3f1c2e-8a4b-4f5e-9c7d-2b1a0e9f8d7c'),
          web: WebInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null) onTap?.call(r.payload!);
        },
      );
      if (askPermission && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      }
      _ready = true;
    } catch (_) {
      _ready = false; // notifications are a convenience; never block the app
    }
  }

  Future<void> show({required int id, required String title, required String body, String? payload, bool call = false}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            call ? 'calls' : 'messages',
            call ? 'Calls' : 'Messages',
            importance: call ? Importance.max : Importance.high,
            priority: Priority.high,
            category: call ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
            // a ringing call fills the screen (also on the lock screen), and
            // stops after 45 s like the call itself
            fullScreenIntent: call,
            ongoing: call,
            timeoutAfter: call ? 45000 : null,
            visibility: NotificationVisibility.private,
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }
}
