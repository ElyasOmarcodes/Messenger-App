import 'dart:async';

import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/strings.dart';
import '../services/messenger.dart';

enum _Step { welcome, email, password, signup, code, forgot, reset }

/// Telegram-style sign-in: one question per page and a round "next" button.
///   welcome → email → password (existing account)
///                   → name + password (new account) → email code
///   password → forgot → code + new password
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final List<_Step> _stack = [_Step.welcome];
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _hide = true;
  int _resendIn = 0;
  Timer? _timer;

  _Step get _step => _stack.last;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _code]) {
      c.dispose();
    }
    _timer?.cancel();
    super.dispose();
  }

  void _go(_Step s) => setState(() {
        _stack.add(s);
        _error = null;
        if (s == _Step.code || s == _Step.reset) {
          _code.clear();
          _startResendTimer();
        }
      });

  bool _back() {
    if (_stack.length <= 1) return false;
    setState(() {
      _stack.removeLast();
      _error = null;
    });
    return true;
  }

  void _startResendTimer() {
    _resendIn = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendIn--);
      if (_resendIn <= 0) t.cancel();
    });
  }

  bool get _validEmail => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _run(Future<String?> Function() action, {_Step? next}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == 'unconfirmed') {
      await AppScope.read(context).resendSignup(_email.text);
      _go(_Step.code);
    } else if (err != null) {
      setState(() => _error = context.tr(err));
    } else if (next != null) {
      _go(next);
    }
  }

  Future<void> _next() async {
    if (_busy) return;
    final app = AppScope.read(context);
    switch (_step) {
      case _Step.welcome:
        _go(_Step.email);
      case _Step.email:
        if (!_validEmail) return setState(() => _error = context.tr('err_email'));
        setState(() => _busy = true);
        final st = await app.emailStatus(_email.text);
        if (!mounted) return;
        setState(() => _busy = false);
        // Older servers without email_status: ask for the password, offer sign-up.
        if (st == null || st == 'active') {
          _go(_Step.password);
        } else if (st == 'unconfirmed') {
          await app.resendSignup(_email.text);
          _go(_Step.code);
        } else {
          _go(_Step.signup);
        }
      case _Step.password:
        await _run(() => app.signIn(_email.text, _password.text));
      case _Step.signup:
        if (_name.text.trim().isEmpty) return setState(() => _error = context.tr('err_name'));
        if (_password.text.length < 8) return setState(() => _error = context.tr('err_password'));
        await _run(() => app.signUp(_name.text, _email.text, _password.text), next: _Step.code);
      case _Step.code:
        if (_code.text.trim().length < 6) return;
        await _run(() => app.verifySignup(_email.text, _code.text));
      case _Step.forgot:
        await _run(() => app.sendResetCode(_email.text), next: _Step.reset);
      case _Step.reset:
        if (_password.text.length < 8) return setState(() => _error = context.tr('err_password'));
        await _run(() => app.resetPassword(_email.text, _code.text, _password.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: _step == _Step.welcome
            ? null
            : AppBar(
                backgroundColor: cs.surface,
                scrolledUnderElevation: 0,
                leading: IconButton(icon: const BackButtonIcon(), onPressed: _back),
              ),
        floatingActionButton: _step == _Step.welcome
            ? null
            : FloatingActionButton(
                tooltip: context.tr('continue'),
                onPressed: _busy ? null : _next,
                child: _busy
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                    : const Icon(Icons.arrow_forward_rounded),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(key: ValueKey(_step), child: _page(context)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _page(BuildContext context) => switch (_step) {
        _Step.welcome => _welcome(context),
        _Step.email => _form(
            icon: Icons.alternate_email_rounded,
            title: context.tr('your_email'),
            sub: context.tr('your_email_sub'),
            fields: [_emailField()],
          ),
        _Step.password => _form(
            icon: Icons.lock_rounded,
            title: context.tr('enter_password'),
            sub: context.tr('enter_password_sub', {'email': _email.text.trim()}),
            fields: [_passwordField('password', AutofillHints.password)],
            extra: Column(children: [
              TextButton(onPressed: () => _go(_Step.forgot), child: Text(context.tr('forgot'))),
              TextButton(onPressed: () => _go(_Step.signup), child: Text(context.tr('no_account'))),
            ]),
          ),
        _Step.signup => _form(
            icon: Icons.person_rounded,
            title: context.tr('your_info'),
            sub: context.tr('your_info_sub'),
            fields: [
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: 40,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: InputDecoration(labelText: context.tr('your_name'), counterText: ''),
              ),
              const SizedBox(height: 14),
              _passwordField('password', AutofillHints.newPassword, autofocus: false),
            ],
          ),
        _Step.code => _form(
            icon: Icons.mark_email_unread_rounded,
            title: context.tr('check_email'),
            sub: context.tr('verify_sub', {'email': _email.text.trim()}),
            fields: [_codeField(autoSubmit: true)],
            extra: _resendButton(() => AppScope.read(context).resendSignup(_email.text)),
          ),
        _Step.forgot => _form(
            icon: Icons.key_rounded,
            title: context.tr('reset_title'),
            sub: context.tr('reset_sub'),
            fields: [_emailField()],
          ),
        _Step.reset => _form(
            icon: Icons.mark_email_unread_rounded,
            title: context.tr('reset_title'),
            sub: context.tr('verify_sub', {'email': _email.text.trim()}),
            fields: [_codeField(autoSubmit: false), const SizedBox(height: 14), _passwordField('new_password', AutofillHints.newPassword, autofocus: false)],
            extra: _resendButton(() => AppScope.read(context).sendResetCode(_email.text)),
          ),
      };

  // ── Pages ──────────────────────────────────────────────────────────────
  Widget _welcome(BuildContext context) {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 24),
      child: Column(
        children: [
          const Spacer(flex: 3),
          const PaighamLogo(size: 132),
          const SizedBox(height: 28),
          Text(context.tr('app_name'), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            context.tr('welcome_points'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15.5, height: 1.6, color: cs.onSurfaceVariant),
          ),
          const Spacer(flex: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final l in AppLang.values)
                ChoiceChip(
                  label: Text(l.label),
                  selected: app.lang == l,
                  showCheckmark: false,
                  onSelected: (_) => app.setLang(l),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: _next, child: Text(context.tr('start_messaging'))),
          ),
        ],
      ),
    );
  }

  Widget _form({required IconData icon, required String title, required String sub, required List<Widget> fields, Widget? extra}) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 120),
      children: [
        Center(
          child: Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 54, color: cs.primary),
          ),
        ),
        const SizedBox(height: 24),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(sub, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.5, color: cs.onSurfaceVariant)),
        const SizedBox(height: 28),
        AutofillGroup(child: Column(children: fields)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Brand.pomegranate, fontWeight: FontWeight.w600)),
          ),
        if (extra != null) Padding(padding: const EdgeInsets.only(top: 18), child: Center(child: extra)),
      ],
    );
  }

  // ── Fields ─────────────────────────────────────────────────────────────
  Widget _emailField() => Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(labelText: context.tr('email'), hintText: 'name@gmail.com'),
          onSubmitted: (_) => _next(),
        ),
      );

  Widget _passwordField(String label, String hint, {bool autofocus = true}) => Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: _password,
          autofocus: autofocus,
          obscureText: _hide,
          autofillHints: [hint],
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            labelText: context.tr(label),
            suffixIcon: IconButton(
              icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          ),
          onSubmitted: (_) => _next(),
        ),
      );

  Widget _codeField({required bool autoSubmit}) => Directionality(
        textDirection: TextDirection.ltr,
        child: TextField(
          controller: _code,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          style: const TextStyle(fontSize: 32, letterSpacing: 14, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(counterText: '', hintText: '------'),
          onChanged: (v) {
            if (autoSubmit && v.trim().length == 6) _next();
          },
        ),
      );

  Widget _resendButton(Future<String?> Function() send) => TextButton(
        onPressed: _resendIn > 0 || _busy
            ? null
            : () async {
                await send();
                if (!mounted) return;
                _startResendTimer();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('code_sent'))));
              },
        child: Text(_resendIn > 0 ? context.tr('resend_in', {'s': context.digits(_resendIn)}) : context.tr('resend')),
      );
}
