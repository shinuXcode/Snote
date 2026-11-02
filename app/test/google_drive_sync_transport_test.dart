import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snote/features/sync/google_drive_sync_transport.dart';
import 'package:snote/features/sync/sync_transport.dart';

void main() {
  test('Google Drive adapter requires an OAuth token', () {
    expect(
      () => GoogleDriveSyncTransport(accessToken: '  '),
      throwsArgumentError,
    );
  });

  test('Google Drive lists only Snote objects from appDataFolder', () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['Authorization'], 'Bearer test-access-token');
      expect(request.url.host, 'www.googleapis.com');
      expect(request.url.queryParameters['q'], contains("'appDataFolder' in parents"));
      return http.Response('''
        {
          "nextPageToken": "next-page-2",
          "files": [
            {
              "id": "drive-id-1",
              "name": "snote_note-01.blob",
              "size": "128",
              "modifiedTime": "2026-11-01T12:00:00.000Z",
              "appProperties": {"sha256": "${List.filled(64, 'b').join()}"}
            },
            {"id":"other","name":"photo.png","size":"12"},
            {"id":"bad","name":"snote_../bad.blob","size":"12"}
          ]
        }
      ''', 200);
    });

    final transport = GoogleDriveSyncTransport(
      accessToken: 'test-access-token',
      client: client,
    );
    await transport.connect();
    expect(transport.kind, SyncProviderKind.googleDrive);
    final page = await transport.listObjects();
    final objects = page.objects;
    expect(page.nextCursor, 'next-page-2');

    expect(objects, hasLength(1));
    expect(objects.single.objectId, 'note-01');
    expect(objects.single.byteLength, 128);
    expect(objects.single.sha256, List.filled(64, 'b').join());
    expect(requests, hasLength(2));
    await transport.disconnect();
  });

  test('Google Drive resolves object IDs to Drive file IDs before download', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/drive/v3/files/drive-file-42' &&
          request.url.queryParameters['alt'] == 'media') {
        return http.Response('encrypted-object', 200);
      }
      if (request.url.path == '/drive/v3/files' &&
          request.url.queryParameters['q']?.contains("snote_blob-42.blob") == true) {
        return http.Response('''
          {"files":[{"id":"drive-file-42","name":"snote_blob-42.blob","size":"15","appProperties":{"sha256":"${List.filled(64, 'c').join()}"}}]}
        ''', 200);
      }
      if (request.url.path == '/drive/v3/files') {
        return http.Response('{"files":[]}', 200);
      }
      return http.Response('not found', 404);
    });

    final transport = GoogleDriveSyncTransport(
      accessToken: 'test-access-token',
      client: client,
    );
    await transport.connect();
    final stream = await transport.downloadObject('blob-42');
    final bytes = await stream.expand((chunk) => chunk).toList();
    expect(String.fromCharCodes(bytes), 'encrypted-object');
    await transport.disconnect();
  });
}
