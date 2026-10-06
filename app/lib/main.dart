import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'app/auth_gate.dart';
import 'app/theme_controller.dart';
import 'data/remote/supabase_service.dart';
import 'ui/snote_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SnoteSupabase.initialize();
  await SnoteThemeController.instance.load();
  runApp(const SnoteApp());
}

class SnoteApp extends StatefulWidget {
  const SnoteApp({super.key});

  @override
  State<SnoteApp> createState() => _SnoteAppState();
}

class _SnoteAppState extends State<SnoteApp> {
  final _theme = SnoteThemeController.instance;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final baseLight = SnoteTheme.light();
    final baseDark = SnoteTheme.dark();
    return MaterialApp(
      title: 'Snote',
      debugShowCheckedModeBanner: false,
      theme: _theme.eInk
          ? baseLight.copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF77746D),
                brightness: Brightness.light,
              ),
              scaffoldBackgroundColor: const Color(0xFFF1EEE7),
            )
          : baseLight,
      darkTheme: _theme.eInk ? baseDark : baseDark,
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
  }

  @override
  void dispose() {
    _theme.removeListener(_refresh);
    super.dispose();
  }
}
