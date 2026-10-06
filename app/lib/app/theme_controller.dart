import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SnoteThemeController extends ChangeNotifier {
  SnoteThemeController._();
  static final instance = SnoteThemeController._();

  final _storage = const FlutterSecureStorage();
  bool eInk = false;

  Future<void> load() async {
    if (kIsWeb) return;
    eInk = (await _storage.read(key: 'snote.eink')) == 'true';
    notifyListeners();
  }

  Future<void> setEInk(bool value) async {
    eInk = value;
    notifyListeners();
    if (!kIsWeb) {
      await _storage.write(key: 'snote.eink', value: value.toString());
    }
  }
}
