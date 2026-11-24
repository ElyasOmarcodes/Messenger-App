import 'package:flutter/material.dart';

import '../brand/brand.dart';
import '../brand/logo.dart';
import '../l10n/strings.dart';
import '../services/messenger.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = context.tr('name_required'));
      return;
    }
    final phone = _phone.text.trim();
    await AppScope.read(context).completeOnboarding(
      name: _name.text,
      phone: phone.isEmpty ? '' : '+93 $phone',
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      backgroundColor: Brand.lapisDeep,
      body: Stack(
        children: [
          const Positioned.fill(child: _HeroBackground()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(32),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 30, offset: const Offset(0, 12)),
                                  ],
                                ),
                                child: PaighamLogo(size: _step == 0 ? 116 : 84),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                context.tr('app_name'),
                                style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, height: 1.2),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                context.tr('tagline'),
                                style: const TextStyle(color: Brand.saffron, fontSize: 17, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: _step == 0 ? _welcome(app) : _profile(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _welcome(AppController app) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(context.tr('welcome_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(context.tr('welcome_sub'), style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant, height: 1.5)),
        const SizedBox(height: 20),
        Text(context.tr('choose_language'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final l in AppLang.values) ...[
              Expanded(
                child: _LangPill(
                  label: l.label,
                  selected: app.lang == l,
                  onTap: () => app.setLang(l),
                ),
              ),
              if (l != AppLang.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => setState(() => _step = 1),
          child: Text(context.tr('get_started')),
        ),
      ],
    );
  }

  Widget _profile() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => setState(() => _step = 0),
              icon: const BackButtonIcon(),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Text(context.tr('create_profile'), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          autofocus: true,
          textInputAction: TextInputAction.next,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: context.tr('your_name'),
            hintText: context.tr('name_hint'),
            prefixIcon: const Icon(Icons.person_rounded),
            errorText: _error,
            counterText: '',
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 12),
        Directionality(
          textDirection: TextDirection.ltr,
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 12,
            decoration: InputDecoration(
              labelText: context.tr('phone_optional'),
              prefixText: '+93  ',
              prefixIcon: const Icon(Icons.phone_rounded),
              counterText: '',
            ),
            onSubmitted: (_) => _finish(),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.tr('profile_note'), style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton(onPressed: _finish, child: Text(context.tr('continue'))),
      ],
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: selected ? cs.primary : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Brand.lapisBright, Brand.lapis, Brand.lapisDeep],
        ),
      ),
      child: Opacity(
        opacity: 0.55,
        child: Theme(
          data: Theme.of(context).copyWith(brightness: Brightness.dark),
          child: const _StarField(),
        ),
      ),
    );
  }
}

class _StarField extends StatelessWidget {
  const _StarField();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StarFieldPainter(), size: Size.infinite);
  }
}

class _StarFieldPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const tile = 64.0;
    final p = Paint()
      ..color = const Color(0x33FFFFFF)
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
