import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sync_transport.dart';

/// Google Drive appDataFolder object storage.
///
/// Supply a short-lived OAuth access token obtained by the host app with the
/// Drive appData scope. This adapter does not perform OAuth or persist tokens.
class GoogleDriveSyncTransport implements SyncTransport {
  GoogleDriveSyncTransport({
    String? accessToken,
    Future<String> Function()? accessTokenProvider,
    http.Client? client,
  })  : _accessToken = accessToken?.trim(),
        _accessTokenProvider = accessTokenProvider,
        _client = client ?? http.Client(),
        _ownsClient = client == null {
    if ((_accessToken == null || _accessToken!.isEmpty) &&
        _accessTokenProvider == null) {
      throw ArgumentError(
        'Provide an access token or an OAuth access-token provider.',
      );
    }
  }

  final String? _accessToken;
  final Future<String> Function()? _accessTokenProvider;
  final http.Client _client;
  final bool _ownsClient;
  bool _connected = false;

  static final Uri _filesUri = Uri.https('www.googleapis.com', '/drive/v3/files');
  static final Uri _uploadUri = Uri.https('www.googleapis.com', '/upload/drive/v3/files', {
    'uploadType': 'multipart',
    'fields': 'id,name,size,modifiedTime,appProperties',
  });

  @override
  SyncProviderKind get kind => SyncProviderKind.googleDrive;

  @override
  SyncTransportCapabilities get capabilities => const SyncTransportCapabilities(
    supportsResumableUpload: false,
    supportsConditionalWrite: false,
    supportsBackgroundOperation: false,
  );

  Uri _objectQuery(String objectId) => _filesUri.replace(queryParameters: {
    'q': "'appDataFolder' in parents and trashed = false and name = 'snote_${objectId}.blob'",
    'fields': 'files(id,name,size,modifiedTime,appProperties)',
    'pageSize': '10',
  });

  Future<String> _currentAccessToken() async {
    final provider = _accessTokenProvider;
    final token = provider == null ? _accessToken : await provider();
    if (token == null || token.trim().isEmpty) {
      throw StateError('Google Drive authorization is unavailable. Reconnect and retry.');
    }
    return token.trim();
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request, {required Set<int> accepted}) async {
    request.followRedirects = false;
    request.headers['Authorization'] = 'Bearer ${await _currentAccessToken()}';
    request.headers['Accept'] = 'application/json, application/octet-stream';
    final response = await _client.send(request);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.drain<void>();
      throw StateError('Google Drive refused a redirect; retry the authenticated request directly.');
    }
    if (!accepted.contains(response.statusCode)) {
      final status = response.statusCode;
      await response.stream.drain<void>();
      if (status == 401 || status == 403) {
        throw StateError('Google Drive authorization failed. Reconnect the Drive account and retry.');
      }
      throw StateError('Google Drive request failed (HTTP $status).');
    }
    return response;
  }

  @override
  Future<void> connect() async {
    await _listPage();
    _connected = true;
  }

  Future<Map<String, dynamic>> _listPage({String? pageToken}) async {
    final query = <String, String>{
      'q': "'appDataFolder' in parents and trashed = false and name contains '.blob'",
      'fields': 'nextPageToken,files(id,name,size,modifiedTime,appProperties)',
      'pageSize': '1000',
    };
    if (pageToken != null && pageToken.isNotEmpty) query['pageToken'] = pageToken;
    final response = await _send(
      http.Request('GET', _filesUri.replace(queryParameters: query)),
      accepted: {200},
    );
    final decoded = jsonDecode(await response.stream.bytesToString());
    if (decoded is! Map) throw const FormatException('Invalid Google Drive listing response.');
    return decoded.cast<String, dynamic>();
  }

  @override
  Future<SyncRemotePage> listObjects({String? cursor}) async {
    _requireConnected();
    final page = await _listPage(pageToken: cursor);
    final files = page['files'];
    if (files is! List) return const SyncRemotePage(objects: []);
    final objects = <SyncRemoteObject>[];
    for (final raw in files.whereType<Map>()) {
      final name = raw['name']?.toString() ?? '';
      if (!name.startsWith('snote_') || !name.endsWith('.blob')) continue;
      final id = name.substring(6, name.length - 5);
      if (!_validId(id)) continue;
      final size = int.tryParse(raw['size']?.toString() ?? '');
      if (size == null || size < 0) continue;
      final properties = raw['appProperties'];
      final sha = properties is Map ? properties['sha256']?.toString() ?? '' : '';
      objects.add(SyncRemoteObject(
        objectId: id,
        sha256: sha,
        byteLength: size,
        createdAt: DateTime.tryParse(raw['modifiedTime']?.toString() ?? '')?.toUtc()
            ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ));
    }
    objects.sort((a, b) => a.objectId.compareTo(b.objectId));
    return SyncRemotePage(
      objects: objects,
      nextCursor: page['nextPageToken']?.toString(),
    );
  }

  bool _validId(String id) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,179}$').hasMatch(id);

  Future<Map<String, dynamic>?> _findObject(String objectId) async {
    if (!_validId(objectId)) {
      throw ArgumentError.value(objectId, 'objectId', 'Invalid sync object ID.');
    }
    final response = await _send(http.Request('GET', _objectQuery(objectId)), accepted: {200});
    final decoded = jsonDecode(await response.stream.bytesToString());
    if (decoded is! Map || decoded['files'] is! List) return null;
    for (final raw in (decoded['files'] as List).whereType<Map>()) {
      if (raw['name'] == 'snote_${objectId}.blob') return raw.cast<String, dynamic>();
    }
    return null;
  }

  @override
  Future<void> uploadObject({
    required String objectId,
    required Stream<List<int>> encryptedBytes,
    required int byteLength,
    required String sha256,
  }) async {
    _requireConnected();
    if (!_validId(objectId) || byteLength < 0 ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('Invalid encrypted object ID, length or SHA-256.');
    }

    final existing = await _findObject(objectId);
    if (existing != null) {
      final properties = existing['appProperties'];
      final existingSha = properties is Map ? properties['sha256']?.toString() : null;
      if (existingSha?.toLowerCase() == sha256.toLowerCase() &&
          int.tryParse(existing['size']?.toString() ?? '') == byteLength) {
        return;
      }
      throw StateError('A different immutable object already uses this ID in Google Drive.');
    }

    final boundary = 'snotee_${DateTime.now().microsecondsSinceEpoch}';
    final metadata = utf8.encode(jsonEncode({
      'name': 'snote_${objectId}.blob',
      'parents': ['appDataFolder'],
      'appProperties': {'sha256': sha256.toLowerCase(), 'format': 'snotee-sync-v1'},
    }));
    final prefix = utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n');
    final middle = utf8.encode('\r\n--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n');
    final suffix = utf8.encode('\r\n--$boundary--\r\n');

    final request = http.StreamedRequest('POST', _uploadUri)
      ..followRedirects = false
      ..contentLength = prefix.length + metadata.length + middle.length + byteLength + suffix.length
      ..headers.addAll({
        'Authorization': 'Bearer ${await _currentAccessToken()}',
        'Content-Type': 'multipart/related; boundary=$boundary',
      });

    final responseFuture = _client.send(request);
    try {
      await request.sink.addStream(Stream<List<int>>.fromIterable([prefix, metadata, middle]));
      await request.sink.addStream(encryptedBytes);
      await request.sink.addStream(Stream<List<int>>.fromIterable([suffix]));
      await request.sink.close();
    } catch (_) {
      await request.sink.close();
      rethrow;
    }

    final response = await responseFuture;
    if (response.statusCode != 200 && response.statusCode != 201) {
      final status = response.statusCode;
      await response.stream.drain<void>();
      if (status == 401 || status == 403) {
        throw StateError('Google Drive authorization failed. Reconnect the Drive account and retry.');
      }
      throw StateError('Google Drive upload failed (HTTP $status).');
    }
    await response.stream.drain<void>();
  }

  @override
  Future<Stream<List<int>>> downloadObject(String objectId) async {
    _requireConnected();
    final file = await _findObject(objectId);
    if (file == null) throw StateError('Sync object was not found in Google Drive.');
    final fileId = file['id']?.toString();
    if (fileId == null ||
        !RegExp(r'^[A-Za-z0-9_-]{5,200}$').hasMatch(fileId)) {
      throw const FormatException('Google Drive returned an invalid file identifier.');
    }
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v3/files/${Uri.encodeComponent(fileId)}',
      {'alt': 'media'},
    );
    final response = await _send(http.Request('GET', uri), accepted: {200});
    return response.stream;
  }

  void _requireConnected() {
    if (!_connected) throw StateError('Connect to Google Drive before syncing.');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    if (_ownsClient) _client.close();
  }
}
