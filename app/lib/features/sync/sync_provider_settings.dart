import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'webdav_sync_transport.dart';

class WebDavCredentials {
  const WebDavCredentials({
    required this.collectionUrl,
    required this.username,
    required this.password,
  });

  final String collectionUrl;
  final String username;
  final String password;

  WebDavSyncTransport createTransport() => WebDavSyncTransport(
        collectionUri: Uri.parse(collectionUrl),
        username: username,
        password: password,
      );
}

/// Provider credentials live in OS-backed secure storage, never in SQLite,
/// change packs, logs or source control.
class SyncProviderSettings {
  SyncProviderSettings({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _webDavUrl = 'snotee.sync.webdav.url.v1';
  static const _webDavUser = 'snotee.sync.webdav.user.v1';
  static const _webDavPassword = 'snotee.sync.webdav.password.v1';

  final FlutterSecureStorage _storage;

  Future<void> saveWebDav({
    required String collectionUrl,
    required String username,
    required String password,
  }) async {
    final uri = Uri.tryParse(collectionUrl.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('Enter a valid HTTPS WebDAV collection URL.');
    }
    if (username.trim().isEmpty || password.isEmpty) {
      throw ArgumentError('WebDAV username and password are required.');
    }
    await _storage.write(key: _webDavUrl, value: uri.toString());
    await _storage.write(key: _webDavUser, value: username.trim());
    await _storage.write(key: _webDavPassword, value: password);
  }

  Future<WebDavCredentials?> readWebDav() async {
    final url = await _storage.read(key: _webDavUrl);
    final user = await _storage.read(key: _webDavUser);
    final password = await _storage.read(key: _webDavPassword);
    if (url == null || user == null || password == null) return null;
    return WebDavCredentials(collectionUrl: url, username: user, password: password);
  }

  Future<void> clearWebDav() async {
    await _storage.delete(key: _webDavUrl);
    await _storage.delete(key: _webDavUser);
    await _storage.delete(key: _webDavPassword);
  }
}
