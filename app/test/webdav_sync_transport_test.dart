import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snote/features/sync/sync_transport.dart';
import 'package:snote/features/sync/webdav_sync_transport.dart';

void main() {
  test('WebDAV refuses insecure URLs and embedded credentials', () {
    expect(
      () => WebDavSyncTransport(
        collectionUri: Uri.parse('http://nas.example.com/snote/'),
        username: 'user',
        password: 'secret',
      ),
      throwsArgumentError,
    );
    expect(
      () => WebDavSyncTransport(
        collectionUri: Uri.parse('https://user:secret@nas.example.com/snote/'),
        username: 'user',
        password: 'secret',
      ),
      throwsArgumentError,
    );
  });

  test('WebDAV lists only validated immutable objects in its collection', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'PROPFIND' && request.headers['Depth'] == '0') {
        return http.Response('', 207);
      }
      if (request.method == 'PROPFIND' && request.headers['Depth'] == '1') {
        return http.Response('''
          <?xml version="1.0"?>
          <d:multistatus xmlns:d="DAV:" xmlns:s="urn:snotee:sync">
            <d:response>
              <d:href>/snote/</d:href>
              <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
            </d:response>
            <d:response>
              <d:href>/snote/abc123.blob</d:href>
              <d:propstat><d:prop>
                <d:getcontentlength>42</d:getcontentlength>
                <d:getlastmodified>Sun, 01 Nov 2026 12:00:00 GMT</d:getlastmodified>
                <s:sha256>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</s:sha256>
              </d:prop></d:propstat>
            </d:response>
            <d:response>
              <d:href>https://evil.example/steal.blob</d:href>
              <d:propstat><d:prop><d:getcontentlength>10</d:getcontentlength></d:prop></d:propstat>
            </d:response>
            <d:response>
              <d:href>/snote/../escape.blob</d:href>
              <d:propstat><d:prop><d:getcontentlength>10</d:getcontentlength></d:prop></d:propstat>
            </d:response>
          </d:multistatus>
        ''', 207);
      }
      return http.Response('', 500);
    });

    final transport = WebDavSyncTransport(
      collectionUri: Uri.parse('https://nas.example.com/snote'),
      username: 'sync-user',
      password: 'not-logged',
      client: client,
    );

    await transport.connect();
    expect(transport.kind, SyncProviderKind.webDav);
    final objects = await transport.listObjects();

    expect(objects, hasLength(1));
    expect(objects.single.objectId, 'abc123');
    expect(objects.single.byteLength, 42);
    expect(objects.single.sha256, 'a' * 64);
    expect(requests.every((request) =>
      request.headers['Authorization'] == 'Basic c3luYy11c2VyOm5vdC1sb2dnZWQ='
    ), isTrue);

    await transport.disconnect();
  });

  test('WebDAV rejects path traversal object IDs before making a request', () async {
    final client = MockClient((request) async => http.Response('', 207));
    final transport = WebDavSyncTransport(
      collectionUri: Uri.parse('https://nas.example.com/snote/'),
      username: 'user',
      password: 'password',
      client: client,
    );
    await transport.connect();
    expect(
      () => transport.downloadObject('../outside'),
      throwsArgumentError,
    );
    await transport.disconnect();
  });
}
