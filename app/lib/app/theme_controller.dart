import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SnoteThemeController extends ChangeNotifier {
  SnoteThemeController._();
  static final instance = SnoteThemeController._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool eInk = false;
  bool grayscale = true;
  bool reduceMotion = false;

  Future<void> load() async {
    if (!kIsWeb) {
      eInk = (await _storage.read(key: 'snote.eink')) == 'true';
      grayscale = (await _storage.read(key: 'snote.eink.grayscale')) != 'false';
      reduceMotion = (await _storage.read(key: 'snote.reduce-motion')) == 'true';
    }
    notifyListeners();
  }

  Future<void> setEInk(bool value) async {
    eInk = value;
    notifyListeners();
    if (!kIsWeb) await _storage.write(key: 'snote.eink', value: value.toString());
  }

  Future<void> setGrayscale(bool value) async {
    grayscale = value;
    notifyListeners();
    if (!kIsWeb) await _storage.write(key: 'snote.eink.grayscale', value: value.toString());
  }

  Future<void> setReduceMotion(bool value) async {
    reduceMotion = value;
    notifyListeners();
    if (!kIsWeb) await _storage.write(key: 'snote.reduce-motion', value: value.toString());
  }
}
