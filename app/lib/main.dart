import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'app/auth_gate.dart';
import 'app/theme_controller.dart';
import 'data/remote/supabase_service.dart';

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
    final seed = _theme.eInk
        ? const Color(0xff77746d)
        : const Color(0xFF7165FF);

    return MaterialApp(
      title: 'Snote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: _theme.eInk
            ? const Color(0xffefede7)
            : const Color(0xFFF5F6FA),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
      ],
      home: const AuthGate(),
    );
  }

  @override
  void dispose() {
    _theme.removeListener(_refresh);
    super.dispose();
  }
}
