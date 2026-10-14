import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/notes/editor_v2/editor_v2_document.dart';
import 'package:snote/features/notes/note_content_compatibility.dart';

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

    test('lazy PDF page references persist without embedding page rasters', () {
      final page = EditorV2DocumentCodec.normalizePage(<String, Object?>{
        'id': 'pdf-source-page-500',
        'template': 'blank',
        'pdfLazyRender': true,
        'pdfSourceAssetId': 'asset-pdf-001',
        'pdfSourceName': 'textbook.pdf',
        'pdfSourceHash': 'sha256-placeholder',
        'pdfSourcePage': 500,
        'strokes': <Object?>[],
        'images': <Object?>[],
        'textBoxes': <Object?>[],
      });
      final payload = EditorV2DocumentCodec.savePayload(
        previousContent: <String, Object?>{},
        pages: <Map<String, Object?>>[page],
        editorMode: 'handwriting',
        bookmarkedPages: <int>[],
        currentPageIndex: 0,
      );
      final restored = EditorV2DocumentCodec.decodePages(
        EditorV2DocumentCodec.decodeRoot(jsonEncode(payload)),
      ).single;

      expect(restored['pdfLazyRender'], isTrue);
      expect(restored['pdfSourceAssetId'], 'asset-pdf-001');
      expect(restored['pdfSourcePage'], 500);
      expect(restored.containsKey('backgroundImage'), isFalse);
    });

    test('PDF restoration only checks pages belonging to the active source', () {
      final pages = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'pdf-a-1',
          'pdfLazyRender': true,
          'pdfSourceAssetId': 'asset-a',
          'pdfSourceName': 'a.pdf',
          'pdfSourceHash': 'hash-a',
          'pdfSourcePage': 1,
        },
        <String, Object?>{
          'id': 'pdf-b-1',
          'pdfLazyRender': true,
          'pdfSourceAssetId': 'asset-b',
          'pdfSourceName': 'b.pdf',
          'pdfSourceHash': 'hash-b',
          'pdfSourcePage': 1,
        },
      ];

      expect(
        shouldRestorePdfPageBackgrounds(pages, sourceHash: 'hash-b'),
        isFalse,
      );
      expect(
        shouldRestorePdfPageBackgrounds(pages, sourceHash: 'changed-hash'),
        isFalse,
      );
    });

    test('PDF restore preserves other PDF pages and their annotations', () {
      final saved = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'source-a-page-1',
          'pdfSourceAssetId': 'asset-a',
          'pdfSourceName': 'a.pdf',
          'pdfSourceHash': 'hash-a',
          'pdfSourcePage': 1,
          'backgroundImage': 'old-a-raster',
          'strokes': <Object?>[
            <String, Object?>{'id': 'stroke-a'},
          ],
        },
        <String, Object?>{
          'id': 'source-b-page-1',
          'pdfSourceAssetId': 'asset-b',
          'pdfSourceName': 'b.pdf',
          'pdfSourceHash': 'hash-b',
          'pdfSourcePage': 1,
          'backgroundImage': 'old-b-raster',
          'strokes': <Object?>[
            <String, Object?>{'id': 'stroke-b'},
          ],
        },
        <String, Object?>{
          'id': 'blank-after-pdf',
          'template': 'dotted',
          'strokes': <Object?>[],
        },
      ];
      final regeneratedB = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'fresh-b-page-1',
          'pdfLazyRender': true,
          'pdfSourceAssetId': 'asset-b',
          'pdfSourceName': 'b.pdf',
          'pdfSourceHash': 'hash-b',
          'pdfSourcePage': 1,
          'strokes': <Object?>[],
        },
        <String, Object?>{
          'id': 'fresh-b-page-2',
          'pdfLazyRender': true,
          'pdfSourceAssetId': 'asset-b',
          'pdfSourceName': 'b.pdf',
          'pdfSourceHash': 'hash-b',
          'pdfSourcePage': 2,
          'strokes': <Object?>[],
        },
      ];

      final merged = mergeSavedAnnotationsWithPdfPages(
        savedPages: saved,
        renderedPages: regeneratedB,
      );

      expect(merged, hasLength(4));
      expect(merged[0]['pdfSourceAssetId'], 'asset-a');
      expect(merged[0]['strokes'], hasLength(1));
      expect(merged[1]['pdfSourceAssetId'], 'asset-b');
      expect(merged[1]['strokes'], hasLength(1));
      expect(merged[1]['pdfLazyRender'], isTrue);
      expect(merged[1].containsKey('backgroundImage'), isFalse);
      expect(merged[2]['pdfSourcePage'], 2);
      expect(merged[3]['id'], 'blank-after-pdf');
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
