import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'brand/brand.dart';
import 'brand/logo.dart';
import 'l10n/strings.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/messenger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  runApp(PaighamApp(controller: controller));
  controller.init();
}

class PaighamApp extends StatelessWidget {
  const PaighamApp({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
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
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                _CupertinoFallbackDelegate(),
              ],
              builder: (context, child) => LangScope(lang: lang, child: child!),
              home: !controller.ready
                  ? const _Splash()
                  : controller.profile == null
                      ? const OnboardingScreen()
                      : const HomeScreen(),
            ),
          );
        },
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
