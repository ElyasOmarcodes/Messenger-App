import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/strings.dart';
import '../services/messenger.dart';

/// Asks for what notifications need on Android, like WhatsApp's first-run
/// page: (1) permission to show notifications (Android 13+), (2) freedom to
/// run in the background (otherwise many phones stop the app and pushes
/// arrive late or never). Shown once after sign-in, and from Settings.
class NotifyScreen extends StatefulWidget {
  const NotifyScreen({super.key, this.page = false});

  /// Opened from Settings (has a back button, no "later").
  final bool page;

  @override
  State<NotifyScreen> createState() => _NotifyScreenState();
}

class _NotifyScreenState extends State<NotifyScreen> with WidgetsBindingObserver {
  static const _sys = MethodChannel('paigham/system');
  bool _notif = false, _battery = false, _checked = false, _askedNotif = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // back from the system settings: look again
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    var n = true, b = true;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        n = await _android?.areNotificationsEnabled() ?? true;
      } catch (_) {}
      try {
        b = await _sys.invokeMethod<bool>('batteryFree') ?? true;
      } catch (_) {}
    }
    if (mounted)
      setState(() {
        _notif = n;
        _battery = b;
        _checked = true;
      });
  }

  Future<void> _next() async {
    if (!_notif) {
      // once refused, Android no longer shows the dialog: open the settings
      if (_askedNotif) {
        await _sys.invokeMethod('notifSettings').catchError((_) => null);
      } else {
        _askedNotif = true;
        try {
          await _android?.requestNotificationsPermission();
        } catch (_) {}
      }
      await _check();
      if (!_notif) return;
    }
    if (!_battery) {
      await _sys.invokeMethod('askBattery').catchError((_) => null);
      return; // checked again on return (resumed)
    }
    _finish();
  }

  void _finish() {
    if (widget.page) {
      Navigator.of(context).maybePop();
    } else {
      AppScope.read(context).setNotifyAsked();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = _notif && _battery;
    return Scaffold(
      appBar: widget.page ? AppBar(title: Text(context.tr('notifications'))) : null,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(Icons.notifications_active_rounded, size: 48, color: cs.primary),
              ),
              const SizedBox(height: 24),
              Text(
                context.tr('nf_title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                context.tr('nf_body'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              _Step(icon: Icons.notifications_rounded, title: context.tr('nf_allow'), sub: context.tr('nf_allow_sub'), done: _notif),
              const SizedBox(height: 10),
              _Step(icon: Icons.battery_charging_full_rounded, title: context.tr('nf_battery'), sub: context.tr('nf_battery_sub'), done: _battery),
              const SizedBox(height: 14),
              Text(
                context.tr('nf_xiaomi'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              TextButton(onPressed: () => _sys.invokeMethod('appSettings').catchError((_) => null), child: Text(context.tr('nf_open_settings'))),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: !_checked ? null : (all ? _finish : _next),
                  style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  child: Text(context.tr(all ? 'nf_done' : 'nf_go'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              if (!widget.page && !all) TextButton(onPressed: _finish, child: Text(context.tr('nf_later'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.sub, required this.done});
  final IconData icon;
  final String title, sub;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                Text(sub, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: done ? const Color(0xFF2DB55D) : cs.outline),
        ],
      ),
    );
  }
}
