import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SnoteThemeStyle { standard, apple, windows, mac }

/// Ten persistent accent palettes; "profile" keeps the selected platform profile.
enum SnoteColorTheme {
  profile('Use interface profile', Color(0xff6c5ce7)),
  violet('Violet', Color(0xff6c5ce7)),
  ocean('Ocean', Color(0xff0077b6)),
  forest('Forest', Color(0xff2d6a4f)),
  rose('Rose', Color(0xffd6336c)),
  sunset('Sunset', Color(0xfff76707)),
  amber('Amber', Color(0xffb7791f)),
  teal('Teal', Color(0xff009688)),
  indigo('Indigo', Color(0xff3949ab)),
  graphite('Graphite', Color(0xff546e7a)),
  emerald('Emerald', Color(0xff10a37f));

  const SnoteColorTheme(this.label, this.color);

  final String label;
  final Color color;

  bool get followsInterfaceProfile => this == SnoteColorTheme.profile;
}

class SnoteThemeController extends ChangeNotifier {
  SnoteThemeController._();
  static final instance = SnoteThemeController._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool eInk = false;
  bool grayscale = true;
  bool reduceMotion = false;
  SnoteThemeStyle style = SnoteThemeStyle.standard;
  SnoteColorTheme colorTheme = SnoteColorTheme.profile;

  Future<void> load() async {
    eInk = (await _storage.read(key: 'snote.eink')) == 'true';
    grayscale = (await _storage.read(key: 'snote.eink.grayscale')) != 'false';
    reduceMotion = (await _storage.read(key: 'snote.reduce-motion')) == 'true';
    final rawStyle = await _storage.read(key: 'snote.theme.style');
    style = SnoteThemeStyle.values.firstWhere(
      (item) => item.name == rawStyle,
      orElse: () => SnoteThemeStyle.standard,
    );
    final rawColorTheme = await _storage.read(key: 'snote.theme.color');
    colorTheme = SnoteColorTheme.values.firstWhere(
      (item) => item.name == rawColorTheme,
      orElse: () => SnoteColorTheme.profile,
    );
    notifyListeners();
  }

  Future<void> setEInk(bool value) async {
    eInk = value;
    notifyListeners();
    await _storage.write(key: 'snote.eink', value: value.toString());
  }

  Future<void> setGrayscale(bool value) async {
    grayscale = value;
    notifyListeners();
    await _storage.write(key: 'snote.eink.grayscale', value: value.toString());
  }

  Future<void> setReduceMotion(bool value) async {
    reduceMotion = value;
    notifyListeners();
    await _storage.write(key: 'snote.reduce-motion', value: value.toString());
  }

  Future<void> setStyle(SnoteThemeStyle value) async {
    style = value;
    notifyListeners();
    await _storage.write(key: 'snote.theme.style', value: value.name);
  }

  Future<void> setColorTheme(SnoteColorTheme value) async {
    colorTheme = value;
    notifyListeners();
    await _storage.write(key: 'snote.theme.color', value: value.name);
  }
}
