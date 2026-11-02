import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'sync_transport.dart';

/// HTTPS WebDAV storage for immutable, already-encrypted sync objects.
class WebDavSyncTransport implements SyncTransport {
  WebDavSyncTransport({
    required Uri collectionUri,
    required this.username,
    required this.password,
    http.Client? client,
  })  : collectionUri = _validateCollectionUri(collectionUri),
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final Uri collectionUri;
  final String username;
  final String password;
  final http.Client _client;
  final bool _ownsClient;
  bool _connected = false;

  static Uri _validateCollectionUri(Uri uri) {
    if (uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw ArgumentError('WebDAV requires an HTTPS collection URL without embedded credentials, query or fragment.');
    }
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path);
  }

  @override
  SyncProviderKind get kind => SyncProviderKind.webDav;

  @override
  SyncTransportCapabilities get capabilities => const SyncTransportCapabilities(
    supportsResumableUpload: false,
    supportsConditionalWrite: true,
    supportsBackgroundOperation: false,
  );

  String get _authorization => "Basic ${base64Encode(utf8.encode('$username:$password'))}";

  Uri _objectUri(String objectId) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,179}$').hasMatch(objectId)) {
      throw ArgumentError.value(objectId, 'objectId', 'Invalid sync object ID.');
    }
    return collectionUri.resolve('${Uri.encodeComponent(objectId)}.blob');
  }

  Uri _digestUri(String objectId) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,179}
    request.followRedirects = false;
    request.headers['Authorization'] = _authorization;
    request.headers['Accept'] = '*/*';
    final response = await _client.send(request);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.drain<void>();
      throw StateError('WebDAV refused a redirect; verify the HTTPS server URL.');
    }
    if (!accepted.contains(response.statusCode)) {
      final status = response.statusCode;
      await response.stream.drain<void>();
      throw StateError('WebDAV request failed (HTTP $status).');
    }
    return response;
  }

  http.Request _request(String method, Uri uri) =>
      http.Request(method, uri)..headers['User-Agent'] = 'Snotee-Sync/1';

  @override
  Future<void> connect() async {
    final probe = _request('PROPFIND', collectionUri)
      ..headers['Depth'] = '0'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';
    final response = await _send(probe, accepted: {200, 207, 404});
    final status = response.statusCode;
    await response.stream.drain<void>();
    if (status == 404) {
      final create = _request('MKCOL', collectionUri);
      final created = await _send(create, accepted: {201, 405});
      await created.stream.drain<void>();
    }
    _connected = true;
  }

  @override
  Future<SyncRemotePage> listObjects({String? cursor}) async {
    _requireConnected();
    if (cursor != null && cursor.isNotEmpty) {
      throw ArgumentError('WebDAV listing does not use continuation cursors.');
    }
    final request = _request('PROPFIND', collectionUri)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:" xmlns:s="urn:snotee:sync">'
          '<d:prop><d:getcontentlength/><d:getlastmodified/><d:getetag/>'
          '<s:sha256/></d:prop></d:propfind>';
    final response = await _send(request, accepted: {200, 207});
    final xml = await response.stream.bytesToString();
    final document = XmlDocument.parse(xml);
    final objects = <SyncRemoteObject>[];

    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'response') continue;
      final href = _descendantText(element, 'href');
      if (href == null || href.isEmpty) continue;
      final resolved = collectionUri.resolve(href);
      if (resolved.origin != collectionUri.origin || !resolved.path.startsWith(collectionUri.path)) continue;
      final filename = Uri.decodeComponent(resolved.pathSegments.isEmpty ? '' : resolved.pathSegments.last);
      if (!filename.endsWith('.blob')) continue;
      final id = filename.substring(0, filename.length - 5);
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,179}$').hasMatch(id)) continue;
      final size = int.tryParse(_descendantText(element, 'getcontentlength') ?? '');
      if (size == null || size < 0) continue;
      final modified = DateTime.tryParse(_descendantText(element, 'getlastmodified') ?? '')?.toUtc()
          ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final digest = await _readDigest(id);
      if (digest == null) {
        throw StateError('WebDAV object $id has no integrity sidecar. Reconnect and retry its upload.');
      }
      objects.add(SyncRemoteObject(
        objectId: id,
        sha256: digest,
        byteLength: size,
        createdAt: modified,
      ));
    }
    objects.sort((a, b) => a.objectId.compareTo(b.objectId));
    return SyncRemotePage(objects: objects);
  }

  String? _descendantText(XmlElement element, String localName) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (child.name.local == localName && child.innerText.trim().isNotEmpty) return child.innerText.trim();
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
    if (byteLength < 0 || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('Invalid encrypted object length or SHA-256.');
    }
    final request = http.StreamedRequest('PUT', _objectUri(objectId))
      ..followRedirects = false
      ..contentLength = byteLength
      ..headers.addAll({
        'Authorization': _authorization,
        'Content-Type': 'application/octet-stream',
        'If-None-Match': '*',
      });
    final responseFuture = _client.send(request);
    try {
      await request.sink.addStream(encryptedBytes);
      await request.sink.close();
    } catch (_) {
      await request.sink.close();
      rethrow;
    }
    final response = await responseFuture;
    if (response.statusCode == 201 || response.statusCode == 204) {
      await response.stream.drain<void>();
      await _writeDigest(objectId, sha256.toLowerCase());
      return;
    }
    if (response.statusCode == 412 || response.statusCode == 409) {
      await response.stream.drain<void>();
      if (await _verifyExistingObject(
        objectId,
        byteLength: byteLength,
        digest: sha256,
      )) {
        return;
      }
      throw StateError('A different immutable object already uses this ID.');
    }
    final status = response.statusCode;
    await response.stream.drain<void>();
    throw StateError('WebDAV upload failed (HTTP $status).');
  }

  @override
  Future<Stream<List<int>>> downloadObject(String objectId) async {
    _requireConnected();
    final response = await _send(_request('GET', _objectUri(objectId)), accepted: {200});
    return response.stream;
  }

  void _requireConnected() {
    if (!_connected) throw StateError('Connect to the WebDAV collection before syncing.');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    if (_ownsClient) _client.close();
  }
}
).hasMatch(objectId)) {
      throw ArgumentError.value(objectId, 'objectId', 'Invalid sync object ID.');
    }
    return collectionUri.resolve('${Uri.encodeComponent(objectId)}.sha256');
  }

  Future<String?> _readDigest(String objectId) async {
    final response = await _send(_request('GET', _digestUri(objectId)), accepted: {200, 404});
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      return null;
    }
    final value = (await response.stream.bytesToString()).trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}
    request.followRedirects = false;
    request.headers['Authorization'] = _authorization;
    request.headers['Accept'] = '*/*';
    final response = await _client.send(request);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.drain<void>();
      throw StateError('WebDAV refused a redirect; verify the HTTPS server URL.');
    }
    if (!accepted.contains(response.statusCode)) {
      final status = response.statusCode;
      await response.stream.drain<void>();
      throw StateError('WebDAV request failed (HTTP $status).');
    }
    return response;
  }

  http.Request _request(String method, Uri uri) =>
      http.Request(method, uri)..headers['User-Agent'] = 'Snotee-Sync/1';

  @override
  Future<void> connect() async {
    final probe = _request('PROPFIND', collectionUri)
      ..headers['Depth'] = '0'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';
    final response = await _send(probe, accepted: {200, 207, 404});
    final status = response.statusCode;
    await response.stream.drain<void>();
    if (status == 404) {
      final create = _request('MKCOL', collectionUri);
      final created = await _send(create, accepted: {201, 405});
      await created.stream.drain<void>();
    }
    _connected = true;
  }

  @override
  Future<SyncRemotePage> listObjects({String? cursor}) async {
    _requireConnected();
    if (cursor != null && cursor.isNotEmpty) {
      throw ArgumentError('WebDAV listing does not use continuation cursors.');
    }
    final request = _request('PROPFIND', collectionUri)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:" xmlns:s="urn:snotee:sync">'
          '<d:prop><d:getcontentlength/><d:getlastmodified/><d:getetag/>'
          '<s:sha256/></d:prop></d:propfind>';
    final response = await _send(request, accepted: {200, 207});
    final xml = await response.stream.bytesToString();
    final document = XmlDocument.parse(xml);
    final objects = <SyncRemoteObject>[];

    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'response') continue;
      final href = _descendantText(element, 'href');
      if (href == null || href.isEmpty) continue;
      final resolved = collectionUri.resolve(href);
      if (resolved.origin != collectionUri.origin || !resolved.path.startsWith(collectionUri.path)) continue;
      final filename = Uri.decodeComponent(resolved.pathSegments.isEmpty ? '' : resolved.pathSegments.last);
      if (!filename.endsWith('.blob')) continue;
      final id = filename.substring(0, filename.length - 5);
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,179}$').hasMatch(id)) continue;
      final size = int.tryParse(_descendantText(element, 'getcontentlength') ?? '');
      if (size == null || size < 0) continue;
      final modified = DateTime.tryParse(_descendantText(element, 'getlastmodified') ?? '')?.toUtc()
          ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      objects.add(SyncRemoteObject(
        objectId: id,
        sha256: _descendantText(element, 'sha256') ?? '',
        byteLength: size,
        createdAt: modified,
      ));
    }
    objects.sort((a, b) => a.objectId.compareTo(b.objectId));
    return SyncRemotePage(objects: objects);
  }

  String? _descendantText(XmlElement element, String localName) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (child.name.local == localName && child.innerText.trim().isNotEmpty) return child.innerText.trim();
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
    if (byteLength < 0 || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('Invalid encrypted object length or SHA-256.');
    }
    final request = http.StreamedRequest('PUT', _objectUri(objectId))
      ..followRedirects = false
      ..contentLength = byteLength
      ..headers.addAll({
        'Authorization': _authorization,
        'Content-Type': 'application/octet-stream',
        'If-None-Match': '*',
        'X-Snote-SHA256': sha256.toLowerCase(),
      });
    final responseFuture = _client.send(request);
    try {
      await request.sink.addStream(encryptedBytes);
      await request.sink.close();
    } catch (_) {
      await request.sink.close();
      rethrow;
    }
    final response = await responseFuture;
    if (response.statusCode == 201 || response.statusCode == 204) {
      await response.stream.drain<void>();
      return;
    }
    if (response.statusCode == 412 || response.statusCode == 409) {
      await response.stream.drain<void>();
      final head = _request('HEAD', _objectUri(objectId));
      final existing = await _send(head, accepted: {200, 404});
      final matches = existing.statusCode == 200 &&
          existing.headers['x-snote-sha256']?.toLowerCase() == sha256.toLowerCase() &&
          existing.headers['content-length'] == byteLength.toString();
      await existing.stream.drain<void>();
      if (matches) return;
      throw StateError('A different immutable object already uses this ID.');
    }
    final status = response.statusCode;
    await response.stream.drain<void>();
    throw StateError('WebDAV upload failed (HTTP $status).');
  }

  @override
  Future<Stream<List<int>>> downloadObject(String objectId) async {
    _requireConnected();
    final response = await _send(_request('GET', _objectUri(objectId)), accepted: {200});
    return response.stream;
  }

  void _requireConnected() {
    if (!_connected) throw StateError('Connect to the WebDAV collection before syncing.');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    if (_ownsClient) _client.close();
  }
}
).hasMatch(value)) {
      throw const FormatException('WebDAV sync digest sidecar is malformed.');
    }
    return value;
  }

  Future<void> _writeDigest(String objectId, String digest) async {
    final request = http.Request('PUT', _digestUri(objectId))
      ..headers['Content-Type'] = 'text/plain; charset=utf-8'
      ..headers['If-None-Match'] = '*'
      ..body = digest.toLowerCase();
    final response = await _send(request, accepted: {201, 204, 412});
    await response.stream.drain<void>();
    if (response.statusCode == 412) {
      final existing = await _readDigest(objectId);
      if (existing != digest.toLowerCase()) {
        throw StateError('A different SHA-256 sidecar already exists for this object.');
      }
    }
  }

  Future<bool> _verifyExistingObject(
    String objectId, {
    required int byteLength,
    required String digest,
  }) async {
    final head = await _send(_request('HEAD', _objectUri(objectId)), accepted: {200, 404});
    if (head.statusCode == 404) {
      await head.stream.drain<void>();
      return false;
    }
    final existingLength = int.tryParse(head.headers['content-length'] ?? '');
    await head.stream.drain<void>();
    if (existingLength != byteLength) return false;

    final existing = await _send(_request('GET', _objectUri(objectId)), accepted: {200});
    final builder = BytesBuilder(copy: false);
    await for (final chunk in existing.stream) {
      builder.add(chunk);
      if (builder.length > byteLength) {
        throw const FormatException('Existing WebDAV object exceeds its declared size.');
      }
    }
    final bytes = builder.takeBytes();
    if (bytes.length != byteLength ||
        sha256.convert(bytes).toString() != digest.toLowerCase()) {
      return false;
    }
    await _writeDigest(objectId, digest);
    return true;
  }

  Future<http.StreamedResponse> _send(http.BaseRequest request, {required Set<int> accepted}) async {
    request.followRedirects = false;
    request.headers['Authorization'] = _authorization;
    request.headers['Accept'] = '*/*';
    final response = await _client.send(request);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.drain<void>();
      throw StateError('WebDAV refused a redirect; verify the HTTPS server URL.');
    }
    if (!accepted.contains(response.statusCode)) {
      final status = response.statusCode;
      await response.stream.drain<void>();
      throw StateError('WebDAV request failed (HTTP $status).');
    }
    return response;
  }

  http.Request _request(String method, Uri uri) =>
      http.Request(method, uri)..headers['User-Agent'] = 'Snotee-Sync/1';

  @override
  Future<void> connect() async {
    final probe = _request('PROPFIND', collectionUri)
      ..headers['Depth'] = '0'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/></d:prop></d:propfind>';
    final response = await _send(probe, accepted: {200, 207, 404});
    final status = response.statusCode;
    await response.stream.drain<void>();
    if (status == 404) {
      final create = _request('MKCOL', collectionUri);
      final created = await _send(create, accepted: {201, 405});
      await created.stream.drain<void>();
    }
    _connected = true;
  }

  @override
  Future<SyncRemotePage> listObjects({String? cursor}) async {
    _requireConnected();
    if (cursor != null && cursor.isNotEmpty) {
      throw ArgumentError('WebDAV listing does not use continuation cursors.');
    }
    final request = _request('PROPFIND', collectionUri)
      ..headers['Depth'] = '1'
      ..headers['Content-Type'] = 'application/xml; charset=utf-8'
      ..body = '<?xml version="1.0" encoding="utf-8"?>'
          '<d:propfind xmlns:d="DAV:" xmlns:s="urn:snotee:sync">'
          '<d:prop><d:getcontentlength/><d:getlastmodified/><d:getetag/>'
          '<s:sha256/></d:prop></d:propfind>';
    final response = await _send(request, accepted: {200, 207});
    final xml = await response.stream.bytesToString();
    final document = XmlDocument.parse(xml);
    final objects = <SyncRemoteObject>[];

    for (final element in document.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'response') continue;
      final href = _descendantText(element, 'href');
      if (href == null || href.isEmpty) continue;
      final resolved = collectionUri.resolve(href);
      if (resolved.origin != collectionUri.origin || !resolved.path.startsWith(collectionUri.path)) continue;
      final filename = Uri.decodeComponent(resolved.pathSegments.isEmpty ? '' : resolved.pathSegments.last);
      if (!filename.endsWith('.blob')) continue;
      final id = filename.substring(0, filename.length - 5);
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,179}$').hasMatch(id)) continue;
      final size = int.tryParse(_descendantText(element, 'getcontentlength') ?? '');
      if (size == null || size < 0) continue;
      final modified = DateTime.tryParse(_descendantText(element, 'getlastmodified') ?? '')?.toUtc()
          ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      objects.add(SyncRemoteObject(
        objectId: id,
        sha256: _descendantText(element, 'sha256') ?? '',
        byteLength: size,
        createdAt: modified,
      ));
    }
    objects.sort((a, b) => a.objectId.compareTo(b.objectId));
    return SyncRemotePage(objects: objects);
  }

  String? _descendantText(XmlElement element, String localName) {
    for (final child in element.descendants.whereType<XmlElement>()) {
      if (child.name.local == localName && child.innerText.trim().isNotEmpty) return child.innerText.trim();
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
    if (byteLength < 0 || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw ArgumentError('Invalid encrypted object length or SHA-256.');
    }
    final request = http.StreamedRequest('PUT', _objectUri(objectId))
      ..followRedirects = false
      ..contentLength = byteLength
      ..headers.addAll({
        'Authorization': _authorization,
        'Content-Type': 'application/octet-stream',
        'If-None-Match': '*',
        'X-Snote-SHA256': sha256.toLowerCase(),
      });
    final responseFuture = _client.send(request);
    try {
      await request.sink.addStream(encryptedBytes);
      await request.sink.close();
    } catch (_) {
      await request.sink.close();
      rethrow;
    }
    final response = await responseFuture;
    if (response.statusCode == 201 || response.statusCode == 204) {
      await response.stream.drain<void>();
      return;
    }
    if (response.statusCode == 412 || response.statusCode == 409) {
      await response.stream.drain<void>();
      final head = _request('HEAD', _objectUri(objectId));
      final existing = await _send(head, accepted: {200, 404});
      final matches = existing.statusCode == 200 &&
          existing.headers['x-snote-sha256']?.toLowerCase() == sha256.toLowerCase() &&
          existing.headers['content-length'] == byteLength.toString();
      await existing.stream.drain<void>();
      if (matches) return;
      throw StateError('A different immutable object already uses this ID.');
    }
    final status = response.statusCode;
    await response.stream.drain<void>();
    throw StateError('WebDAV upload failed (HTTP $status).');
  }

  @override
  Future<Stream<List<int>>> downloadObject(String objectId) async {
    _requireConnected();
    final response = await _send(_request('GET', _objectUri(objectId)), accepted: {200});
    return response.stream;
  }

  void _requireConnected() {
    if (!_connected) throw StateError('Connect to the WebDAV collection before syncing.');
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    if (_ownsClient) _client.close();
  }
}
