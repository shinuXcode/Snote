import 'package:flutter/material.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'app/auth_gate.dart';
import 'app/theme_controller.dart';
import 'core/settings/app_settings.dart';
import 'data/remote/supabase_service.dart';
import 'ui/snote_theme.dart';

Future<void> main() async {
  FlutterCryptography.enable();
  WidgetsFlutterBinding.ensureInitialized();
  await SnoteSupabase.initialize();
  await SnoteThemeController.instance.load();
  await SnoteSettings.instance.load();
  runApp(const SnoteApp());
}

class SnoteApp extends StatefulWidget {
  const SnoteApp({super.key});
  @override State<SnoteApp> createState() => _SnoteAppState();
}

class _SnoteAppState extends State<SnoteApp> {
  final _theme = SnoteThemeController.instance;
  @override
  void initState() { super.initState(); _theme.addListener(_refresh); }
  void _refresh() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final light = SnoteTheme.light();
    final dark = SnoteTheme.dark();
    final styleSeed = switch (_theme.style) {
      SnoteThemeStyle.apple => const Color(0xff007aff),
      SnoteThemeStyle.windows => const Color(0xff0078d4),
      SnoteThemeStyle.mac => const Color(0xff8e8e93),
      SnoteThemeStyle.standard => SnoteTheme.violet,
    };
    final app = MaterialApp(
      title: 'Snote',
      debugShowCheckedModeBanner: false,
      theme: _theme.eInk
          ? ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.grey,
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: const Color(0xffededed),
              cardTheme: CardThemeData(
                color: const Color(0xfff7f7f7),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              pageTransitionsTheme: _theme.reduceMotion
                  ? const PageTransitionsTheme(builders: {})
                  : const PageTransitionsTheme(),
            )
          : light.copyWith(
              colorScheme: ColorScheme.fromSeed(seedColor: styleSeed),
            ),
      darkTheme: dark,
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('hi')],
      home: const AuthGate(),
    );
    if (_theme.eInk && _theme.grayscale) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          .2126, .7152, .0722, 0, 0,
          .2126, .7152, .0722, 0, 0,
          .2126, .7152, .0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: app,
      );
    }
    return app;
  }

  @override
  void dispose() { _theme.removeListener(_refresh); super.dispose(); }
}