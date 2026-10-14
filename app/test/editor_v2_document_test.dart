import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/notes/editor_v2/editor_v2_document.dart';

void main() {
  group('EditorV2DocumentCodec', () {
    test('creates a normalized page for a genuinely empty note', () {
      final root = EditorV2DocumentCodec.decodeRoot(null);
      final pages = EditorV2DocumentCodec.decodePages(root);
      expect(pages, isEmpty);

      final page = EditorV2DocumentCodec.normalizePage(<String, Object?>{});
      expect(page['id'], isNotEmpty);
      expect(page['template'], 'dotted');
      expect(page['strokes'], isEmpty);
      expect(page['images'], isEmpty);
      expect(page['textBoxes'], isEmpty);
    });

    test('restores legacy single-page notes without discarding strokes', () {
      final root = EditorV2DocumentCodec.decodeRoot(
        '{"strokes":[{"id":"s1","points":[{"x":4,"y":8}]}],"template":"lined"}',
      );
      final pages = EditorV2DocumentCodec.decodePages(root);

      expect(pages, hasLength(1));
      expect(pages.single['template'], 'lined');
      expect(pages.single['strokes'], hasLength(1));
    });

    test('save preserves unknown metadata, rich-text delta, and page position', () {
      final previous = <String, Object?>{
        'coverKey': 'cover:12',
        'customExtension': <String, Object?>{'futureField': 42},
      };
      final page = EditorV2DocumentCodec.normalizePage(<String, Object?>{
        'id': 'page-1',
        'strokes': <Object?>[],
      });
      final payload = EditorV2DocumentCodec.savePayload(
        previousContent: previous,
        pages: <Map<String, Object?>>[page],
        editorMode: 'text',
        bookmarkedPages: <int>[1],
        textDelta: <dynamic>[
          <String, Object?>{'insert': 'hello'},
          <String, Object?>{'insert': '\n'},
        ],
        currentPageIndex: 0,
      );

      expect(payload['coverKey'], 'cover:12');
      expect(payload['customExtension'], <String, Object?>{'futureField': 42});
      expect(payload['text_delta'], hasLength(2));
      expect(payload['editorMode'], 'text');
      expect(payload['currentPageIndex'], 0);
      expect(payload['bookmarkedPages'], <int>[1]);
      expect(payload['pages'], hasLength(1));
    });

    test('rejects malformed page envelopes rather than making a blank page', () {
      final root = EditorV2DocumentCodec.decodeRoot('{"pages":"not-a-list"}');
      expect(() => EditorV2DocumentCodec.decodePages(root), throwsFormatException);
    });

    test('page indices are safely clamped after insertions/deletions', () {
      expect(EditorV2DocumentCodec.clampPage(-1, 3), 0);
      expect(EditorV2DocumentCodec.clampPage(99, 3), 2);
      expect(EditorV2DocumentCodec.clampPage(99, 0), 0);
    });

    test('page snapshots are deeply independent', () {
      final input = <Map<String, Object?>>[
        <String, Object?>{'id': 'page-1', 'strokes': <Object?>[<String, Object?>{'id': 'stroke-1'}]},
      ];
      final clone = EditorV2DocumentCodec.clonePages(input);
      (clone.first['strokes'] as List).clear();
      expect((input.first['strokes'] as List), hasLength(1));
    });
  });
}
