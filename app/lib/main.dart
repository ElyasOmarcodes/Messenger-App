import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'brand/brand.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'brand/logo.dart';
import 'config.dart';
import 'l10n/strings.dart';
import 'screens/home_screen.dart';
import 'screens/key_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/call_screen.dart';
import 'services/calls.dart';
import 'services/messenger.dart';
import 'services/notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  if (AppConfig.configured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
  }
  final controller = AppController();
  final calls = CallController(controller);
  runApp(PaighamApp(controller: controller, calls: calls));
  controller.init();
  Notifier.instance.init();
}

class PaighamApp extends StatelessWidget {
  const PaighamApp({super.key, required this.controller, required this.calls});
  final AppController controller;
  final CallController calls;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: CallScope(
        controller: calls,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final lang = controller.lang;
            return LangScope(
              lang: lang,
              child: MaterialApp(
                title: Brand.nameLatin,
                debugShowCheckedModeBanner: false,
                theme: Brand.theme(Brightness.light),
                darkTheme: Brand.theme(Brightness.dark),
                themeMode: controller.themeMode,
                locale: Locale(lang.code),
                supportedLocales: [for (final l in AppLang.values) Locale(l.code)],
                localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, _CupertinoFallbackDelegate()],
                builder: (context, child) => BackdropGroup(
                  child: LangScope(
                    lang: lang,
                    // The call screen floats above every page, including open chats.
                    child: ListenableBuilder(
                      listenable: calls,
                      builder: (context, _) => calls.phase == CallPhase.idle
                          ? child!
                          : Stack(
                              children: [
                                child!,
                                const Positioned.fill(child: CallOverlay()),
                              ],
                            ),
                    ),
                  ),
                ),
                home: !AppConfig.configured
                    ? const _NoServer()
                    : !controller.ready
                    ? const _Splash()
                    : controller.session == null
                    ? const OnboardingScreen()
                    // end-to-end key first: create a PIN, or restore with it
                    : switch (controller.keyState) {
                        KeyState.needCreate || KeyState.needRestore || KeyState.needStrengthen || KeyState.offline => const KeyScreen(),
                        _ => const HomeScreen(),
                      },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Brand.lapis,
    body: Center(child: PaighamLogo(size: 120)),
  );
}

class _NoServer extends StatefulWidget {
  const _NoServer();

  @override
  State<_NoServer> createState() => _NoServerState();
}

class _NoServerState extends State<_NoServer> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  bool _busy = false;

  Future<void> _connect() async {
    final url = _url.text.trim();
    if (!url.startsWith('http') || _key.text.trim().length < 20) return;
    setState(() => _busy = true);
    await AppConfig.save(url, _key.text);
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseAnonKey);
    if (!mounted) return;
    await AppScope.read(context).init();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Brand.lapis,
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PaighamLogo(size: 88),
              const SizedBox(height: 16),
              Text(
                context.tr('server_missing'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Column(
                      children: [
                        TextField(
                          controller: _url,
                          decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://xxxx.supabase.co'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _key,
                          decoration: const InputDecoration(labelText: 'Anon / publishable key'),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(onPressed: _busy ? null : _connect, child: Text(context.tr('connect'))),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Flutter ships Material translations for Pashto but not Cupertino ones;
/// this keeps iOS-style widgets working (they fall back to Dari or English).
class _CupertinoFallbackDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoFallbackDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<CupertinoLocalizations> load(Locale locale) {
    final target = locale.languageCode == 'ps' ? const Locale('fa') : locale;
    if (GlobalCupertinoLocalizations.delegate.isSupported(target)) {
      return GlobalCupertinoLocalizations.delegate.load(target);
    }
    return DefaultCupertinoLocalizations.load(locale);
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) => false;
}
