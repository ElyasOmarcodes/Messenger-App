import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../l10n/strings.dart';
import '../services/e2e.dart';
import '../services/messenger.dart';

/// End-to-end key: create a PIN (first time) or open the backup with it
/// (new phone). Shown before the chats until the key is on this phone.
class KeyScreen extends StatefulWidget {
  const KeyScreen({super.key});

  @override
  State<KeyScreen> createState() => _KeyScreenState();
}

class _KeyScreenState extends State<KeyScreen> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  /// "Forgot PIN" turns the restore screen into the create screen.
  bool _forceCreate = false;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit(AppController app, bool create) async {
    final pin = _pin.text;
    final weak = create ? E2E.pinProblem(pin) : null;
    if (weak != null) return setState(() => _error = weak);
    if (create && pin != _again.text) return setState(() => _error = 'pin_mismatch');
    setState(() {
      _busy = true;
      _error = null;
    });
    // Argon2id takes a few seconds on purpose (slow for guessing, too)
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final err = !create
        ? await app.restoreKeys(pin)
        : app.keyState == KeyState.needStrengthen
        ? await app.changePin(pin)
        : await app.createKeys(pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _forgot() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (d) => CupertinoAlertDialog(
        title: Text(d.tr('pin_forgot')),
        content: Text(d.tr('pin_forgot_q')),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(d, false), child: Text(d.tr('cancel'))),
          CupertinoDialogAction(isDestructiveAction: true, onPressed: () => Navigator.pop(d, true), child: Text(d.tr('continue'))),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _forceCreate = true;
        _pin.clear();
        _again.clear();
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    if (app.keyState == KeyState.offline) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.wifi_off_rounded, size: 56, color: cs.primary),
                  const SizedBox(height: 16),
                  Text(context.tr('e2e_offline'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: app.checkKeyBackup, child: Text(context.tr('retry'))),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final strengthen = app.keyState == KeyState.needStrengthen;
    final create = _forceCreate || strengthen || app.keyState == KeyState.needCreate;
    InputDecoration deco(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      suffixIcon: IconButton(onPressed: () => setState(() => _hide = !_hide), icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded)),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(Icons.lock_rounded, size: 46, color: cs.primary),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    context.tr(strengthen ? 'pin_strengthen_title' : (create ? 'e2e_create_title' : 'e2e_restore_title')),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr(strengthen ? 'pin_strengthen_body' : (create ? 'e2e_create_body' : 'e2e_restore_body')),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.5, height: 1.6, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _pin,
                    obscureText: _hide,
                    enabled: !_busy,
                    autofocus: true,
                    textDirection: TextDirection.ltr,
                    decoration: deco(context.tr('pin_hint')),
                    onSubmitted: create ? null : (_) => _submit(app, false),
                  ),
                  if (create) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _again,
                      obscureText: _hide,
                      enabled: !_busy,
                      textDirection: TextDirection.ltr,
                      decoration: deco(context.tr('pin_again')),
                      onSubmitted: (_) => _submit(app, true),
                    ),
                    const SizedBox(height: 10),
                    Text(context.tr('pin_tip'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      context.tr(_error!),
                      style: const TextStyle(color: Brand.pomegranate, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _submit(app, create),
                      child: _busy
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
                                const SizedBox(width: 12),
                                Text(context.tr('pin_working')),
                              ],
                            )
                          : Text(context.tr('continue'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (!create) ...[const SizedBox(height: 8), TextButton(onPressed: _busy ? null : _forgot, child: Text(context.tr('pin_forgot')))],
                  if (!strengthen) ...[const SizedBox(height: 8), TextButton(onPressed: _busy ? null : app.signOut, child: Text(context.tr('logout')))],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
