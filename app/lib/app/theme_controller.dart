import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SnoteThemeStyle { standard, apple, windows, mac }

class SnoteThemeController extends ChangeNotifier {
  SnoteThemeController._();
  static final instance = SnoteThemeController._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  bool eInk = false;
  bool grayscale = true;
  bool reduceMotion = false;
  SnoteThemeStyle style = SnoteThemeStyle.standard;

  Future<void> load() async {
    eInk = (await _storage.read(key: 'snote.eink')) == 'true';
    grayscale = (await _storage.read(key: 'snote.eink.grayscale')) != 'false';
    reduceMotion = (await _storage.read(key: 'snote.reduce-motion')) == 'true';
    final rawStyle = await _storage.read(key: 'snote.theme.style');
    style = SnoteThemeStyle.values.firstWhere(
      (item) => item.name == rawStyle,
      orElse: () => SnoteThemeStyle.standard,
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
}
