import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/strings.dart';
import '../services/messenger.dart';

enum _Step { welcome, login, signup, verify, forgot, reset }

/// Account screens: welcome, log in, sign up, email code, password reset.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.welcome;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _error;
  String? _info;
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  void _go(_Step s) => setState(() {
        _step = s;
        _error = null;
        _info = null;
        _code.clear();
      });

  bool _validEmail() => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _run(Future<String?> Function() action, {_Step? next, String? info}) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    if (err == 'unconfirmed') {
      await AppScope.read(context).resendSignup(_email.text);
      _go(_Step.verify);
      return;
    }
    if (err != null) {
      setState(() => _error = context.tr(err));
    } else if (next != null) {
      _go(next);
      if (info != null) setState(() => _info = context.tr(info));
    }
  }

  Future<void> _submit() async {
    final app = AppScope.read(context);
    switch (_step) {
      case _Step.welcome:
        break;
      case _Step.login:
        if (!_validEmail()) return setState(() => _error = context.tr('err_email'));
        await _run(() => app.signIn(_email.text, _password.text));
      case _Step.signup:
        if (_name.text.trim().isEmpty) return setState(() => _error = context.tr('err_name'));
        if (!_validEmail()) return setState(() => _error = context.tr('err_email'));
        if (_password.text.length < 8) return setState(() => _error = context.tr('err_password'));
        await _run(() => app.signUp(_name.text, _email.text, _password.text), next: _Step.verify);
      case _Step.verify:
        await _run(() => app.verifySignup(_email.text, _code.text));
      case _Step.forgot:
        if (!_validEmail()) return setState(() => _error = context.tr('err_email'));
        await _run(() => app.sendResetCode(_email.text), next: _Step.reset, info: 'code_sent');
      case _Step.reset:
        if (_password.text.length < 8) return setState(() => _error = context.tr('err_password'));
        await _run(() => app.resetPassword(_email.text, _code.text, _password.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.lapisDeep,
      body: Stack(
        children: [
          const Positioned.fill(child: _HeroBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 12))],
                        ),
                        child: PaighamLogo(size: _step == _Step.welcome ? 112 : 76),
                      ),
                      const SizedBox(height: 16),
                      Text(context.tr('app_name'),
                          style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, height: 1.2)),
                      Text(context.tr('tagline'),
                          style: const TextStyle(color: Brand.accent, fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 28),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          child: _step == _Step.welcome ? _welcome() : _form(),
                        ),
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

  Widget _welcome() {
    final app = AppScope.of(context);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('welcome_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(context.tr('welcome_sub'), style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: 18),
        Text(context.tr('choose_language'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final l in AppLang.values) ...[
              Expanded(child: _LangPill(label: l.label, selected: app.lang == l, onTap: () => app.setLang(l))),
              if (l != AppLang.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 22),
        FilledButton(onPressed: () => _go(_Step.signup), child: Text(context.tr('create_account'))),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(64, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          onPressed: () => _go(_Step.login),
          child: Text(context.tr('login'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _form() {
    final cs = Theme.of(context).colorScheme;
    final (title, button) = switch (_step) {
      _Step.login => ('login', 'login'),
      _Step.signup => ('create_account', 'create_account'),
      _Step.verify => ('verify_title', 'verify'),
      _Step.forgot => ('reset_title', 'send_code'),
      _Step.reset => ('reset_title', 'save_password'),
      _Step.welcome => ('', ''),
    };
    final showEmail = _step != _Step.verify && _step != _Step.reset;
    final showPassword = _step == _Step.login || _step == _Step.signup || _step == _Step.reset;
    final showCode = _step == _Step.verify || _step == _Step.reset;

    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => _go(_step == _Step.verify ? _Step.signup : (_step == _Step.reset ? _Step.forgot : _Step.welcome)),
                icon: const BackButtonIcon(),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(child: Text(context.tr(title), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 8),
          if (_step == _Step.verify || _step == _Step.forgot || _step == _Step.reset)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _step == _Step.forgot ? context.tr('reset_sub') : context.tr('verify_sub', {'email': _email.text.trim()}),
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
              ),
            ),
          if (_step == _Step.signup) ...[
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              maxLength: 40,
              autofillHints: const [AutofillHints.name],
              decoration: InputDecoration(
                labelText: context.tr('your_name'),
                hintText: context.tr('name_hint'),
                prefixIcon: const Icon(Icons.person_rounded),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showEmail) ...[
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: InputDecoration(labelText: context.tr('email'), prefixIcon: const Icon(Icons.alternate_email_rounded)),
                onSubmitted: (_) => _step == _Step.forgot ? _submit() : null,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showCode) ...[
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofillHints: const [AutofillHints.oneTimeCode],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w800),
                decoration: InputDecoration(labelText: context.tr('code'), counterText: ''),
                onSubmitted: (_) => _step == _Step.verify ? _submit() : null,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (showPassword) ...[
            Directionality(
              textDirection: TextDirection.ltr,
              child: TextField(
                controller: _password,
                obscureText: _hide,
                autofillHints: [_step == _Step.login ? AutofillHints.password : AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: context.tr(_step == _Step.reset ? 'new_password' : 'password'),
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                    onPressed: () => setState(() => _hide = !_hide),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_error!, style: const TextStyle(color: Brand.pomegranate, fontWeight: FontWeight.w600)),
            ),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(_info!, style: const TextStyle(color: Color(0xFF1E8C6E), fontWeight: FontWeight.w600)),
            ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Text(context.tr(button)),
          ),
          const SizedBox(height: 6),
          if (_step == _Step.login) ...[
            TextButton(onPressed: () => _go(_Step.forgot), child: Text(context.tr('forgot'))),
            TextButton(onPressed: () => _go(_Step.signup), child: Text(context.tr('no_account'))),
          ],
          if (_step == _Step.signup) TextButton(onPressed: () => _go(_Step.login), child: Text(context.tr('have_account'))),
          if (_step == _Step.verify)
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(() => AppScope.read(context).resendSignup(_email.text)).then((_) {
                        if (mounted && _error == null) setState(() => _info = context.tr('code_sent'));
                      }),
              child: Text(context.tr('resend')),
            ),
        ],
      ),
    );
  }
}

class _LangPill extends StatelessWidget {
  const _LangPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? cs.primary : Colors.transparent, width: 1.6),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Center(
            child: Text(label,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: selected ? cs.primary : cs.onSurface)),
          ),
        ),
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Brand.lapisBright, Brand.lapis, Brand.lapisDeep],
          ),
        ),
        child: CustomPaint(painter: _StarFieldPainter(), size: Size.infinite),
      );
}

class _StarFieldPainter extends CustomPainter {
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 64.0;
    final p = Paint()
      ..color = const Color(0x22FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height + tile; y += tile) {
      final odd = (y / tile).round().isOdd;
      for (var x = odd ? tile / 2 : 0.0; x < size.width + tile; x += tile) {
        canvas.drawPath(starPath(Offset(x, y), 14, 8, 8, rotation: 0.39), p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
