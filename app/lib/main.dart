import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'app/app_entry.dart';
import 'ui/snote_logo.dart';
import 'app/theme_controller.dart';
import 'core/settings/app_settings.dart';
import 'ui/snote_theme.dart';

void _installSnoteErrorLogging() {
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    debugPrint('[Snote][FlutterError] ${details.exceptionAsString()}');
    if (details.stack != null) {
      debugPrintStack(stackTrace: details.stack);
    }
    if (previousFlutterError != null) {
      previousFlutterError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final previousPlatformError = dispatcher.onError;
  dispatcher.onError = (error, stackTrace) {
    debugPrint('[Snote][PlatformError] $error\n$stackTrace');
    return previousPlatformError?.call(error, stackTrace) ?? false;
  };
}

Widget _snoteErrorWidget(FlutterErrorDetails details) {
  debugPrint('[Snote][ErrorWidget] ${details.exceptionAsString()}');
  if (details.stack != null) debugPrintStack(stackTrace: details.stack);
  return Material(
    color: const Color(0xfff7f8fa),
    child: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 42, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text('This screen could not be rendered.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('Your saved notes have not been deleted. Return and reopen the note.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              SelectableText(details.exceptionAsString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = _snoteErrorWidget;
  _installSnoteErrorLogging();
  // Mount Flutter immediately so startup failures can show an error/retry
  // screen instead of leaving the user on a blank launch surface.
  runApp(const SnoteApp());
}

class SnoteApp extends StatefulWidget {
  const SnoteApp({super.key});
  @override State<SnoteApp> createState() => _SnoteAppState();
}

class _SnoteAppState extends State<SnoteApp> {
  final _theme = SnoteThemeController.instance;
  bool _bootstrapping = true;
  bool _bootstrapAttemptActive = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    _theme.addListener(_refresh);
    unawaited(_initialize());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    if (_bootstrapAttemptActive) return;
    _bootstrapAttemptActive = true;
    if (mounted) {
      setState(() {
        _bootstrapping = true;
        _startupError = null;
      });
    }

    try {
      await _theme.load();
      await SnoteSettings.instance.load();
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _startupError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Snote startup failed: $error\\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _bootstrapping = false;
        _startupError = error.toString();
      });
    } finally {
      _bootstrapAttemptActive = false;
    }
  }

  void _retryBootstrap() => unawaited(_initialize());

  @override
  Widget build(BuildContext context) {
    final light = SnoteTheme.light();
    final dark = SnoteTheme.dark();
    final profileSeed = switch (_theme.style) {
      SnoteThemeStyle.apple => const Color(0xff007aff),
      SnoteThemeStyle.windows => const Color(0xff0078d4),
      SnoteThemeStyle.mac => const Color(0xff8e8e93),
      SnoteThemeStyle.linux => const Color(0xffe95420),
      SnoteThemeStyle.mobile => const Color(0xff009688),
      SnoteThemeStyle.tablet => const Color(0xff3949ab),
      SnoteThemeStyle.standard => SnoteTheme.violet,
    };
    final seedColor = _theme.colorTheme.followsInterfaceProfile
        ? profileSeed
        : _theme.colorTheme.color;
    final app = MaterialApp(
      title: 'Snote',
      debugShowCheckedModeBanner: false,
      theme: _theme.eInk
          ? ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.grey,
                brightness: Brightness.light,
                contrastLevel: 1.0,
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
              colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.light, contrastLevel: 1.0),
              visualDensity: _theme.style == SnoteThemeStyle.windows || _theme.style == SnoteThemeStyle.linux
                  ? VisualDensity.compact
                  : VisualDensity.standard,
            ),
      darkTheme: dark.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
          contrastLevel: 1.0,
        ),
        visualDensity: _theme.style == SnoteThemeStyle.windows || _theme.style == SnoteThemeStyle.linux
            ? VisualDensity.compact
            : VisualDensity.standard,
      ),
      themeMode: _theme.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('hi')],
      home: _bootstrapping
          ? const _StartupPage()
          : _startupError == null
              ? const AppEntry()
              : _StartupFailurePage(
                  details: _startupError!,
                  onRetry: _retryBootstrap,
                ),
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
  void dispose() {
    _theme.removeListener(_refresh);
    super.dispose();
  }
}

class _StartupPage extends StatelessWidget {
  const _StartupPage();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                TweenAnimationBuilder<double>(
                  tween: Tween(begin: .72, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) => Opacity(
                    opacity: scale.clamp(0.0, 1.0),
                    child: Transform.scale(scale: scale, child: child),
                  ),
                  child: const SnoteLogo(size: 112, showWordmark: false),
                ),
                const SizedBox(height: 24),
                Text('Snote', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 18),
                SizedBox(width: 120, child: LinearProgressIndicator(borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 12),
                const Text('Preparing your notebook'),
              ],
            ),
          ),
        ),
      );
}

class _StartupFailurePage extends StatelessWidget {
  final String details;
  final VoidCallback onRetry;

  const _StartupFailurePage({
    required this.details,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Snote could not finish starting.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your saved notes have not been deleted. Retry startup; '
                      'if this keeps happening, share the details below.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(details, textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry startup'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}