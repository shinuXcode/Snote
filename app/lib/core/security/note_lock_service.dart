import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class NoteLockService {
  final _auth = LocalAuthentication();
  final _storage = const FlutterSecureStorage();

  String _key(String noteId) => 'snote.lock.$noteId';

  Future<bool> isLocked(String noteId) async {
    if (kIsWeb) return false;
    return (await _storage.read(key: _key(noteId))) == 'true';
  }

  Future<void> setLocked(String noteId, bool locked) async {
    if (kIsWeb) return;
    await _storage.write(key: _key(noteId), value: locked.toString());
  }

  Future<bool> authenticate() async {
    if (kIsWeb) return true;

    try {
      if (!await _auth.isDeviceSupported()) return false;

      return await _auth.authenticate(
        localizedReason: 'Authenticate to open your locked Snote',
        persistAcrossBackgrounding: true,
      );
    } on LocalAuthException {
      return false;
    }
  }
}
