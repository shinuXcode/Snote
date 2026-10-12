import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/notes/note_content_compatibility.dart';

void main() {
  test('restores early single-page handwriting notes', () {
    final legacy = <String, Object?>{
      'template': 'blank',
      'strokes': <Object?>[
        <String, Object?>{
          'id': 'stroke-1',
          'points': <Object?>[
            <String, Object?>{'x': 12, 'y': 20},
            <String, Object?>{'x': 40, 'y': 50},
          ],
        },
      ],
    };

    final restored = legacyPageFromNoteContent(legacy);

    expect(restored, isNotNull);
    expect(restored!['template'], 'blank');
    expect(restored['strokes'], same(legacy['strokes']));
    expect(legacy.containsKey('pages'), isFalse);
  });

  test('restores an imported PDF page saved without a pages envelope', () {
    const image = 'iVBORw0KGgo=';
    final legacy = <String, Object?>{
      'backgroundImage': image,
      'pdfSourceName': 'worksheet.pdf',
      'pdfSourcePage': 1,
    };

    final restored = legacyPageFromNoteContent(legacy);

    expect(restored?['backgroundImage'], image);
    expect(restored?['pdfSourceName'], 'worksheet.pdf');
  });

  test('restores persisted editor mode and detects older text-only notes', () {
    expect(
      restoreNoteDrawMode(
        savedMode: 'text',
        textDelta: <Object?>[],
        hasVisibleCanvasContent: true,
      ),
      isFalse,
    );
    expect(
      restoreNoteDrawMode(
        savedMode: null,
        textDelta: <Object?>[
          <String, Object?>{'insert': 'My saved text\n'},
        ],
        hasVisibleCanvasContent: false,
      ),
      isFalse,
    );
    expect(
      restoreNoteDrawMode(
        savedMode: null,
        textDelta: <Object?>[
          <String, Object?>{'insert': '\n'},
        ],
        hasVisibleCanvasContent: true,
      ),
      isNull,
    );
    expect(
      restoreNoteDrawMode(
        savedMode: null,
        textDelta: <Object?>[
          <String, Object?>{'insert': 'PDF text extraction'},
        ],
        hasVisibleCanvasContent: true,
      ),
      isNull,
    );
  });

  test('recovers PDF pages when a stale blank page envelope exists', () {
    expect(shouldRestorePdfPageBackgrounds(<Map<String, Object?>>[]), isTrue);
    expect(
      shouldRestorePdfPageBackgrounds(<Map<String, Object?>>[
        <String, Object?>{
          'template': 'blank',
          'strokes': <Object?>[],
          'images': <Object?>[],
        },
      ]),
      isTrue,
    );
    expect(
      shouldRestorePdfPageBackgrounds(<Map<String, Object?>>[
        <String, Object?>{
          'pdfSourceName': 'worksheet.pdf',
          'pdfSourcePage': 1,
          'strokes': <Object?>[
            <String, Object?>{'id': 'stroke-1'},
          ],
        },
      ]),
      isTrue,
    );
    expect(
      shouldRestorePdfPageBackgrounds(<Map<String, Object?>>[
        <String, Object?>{
          'backgroundImage': 'existing-pdf-image',
          'pdfSourceName': 'worksheet.pdf',
          'pdfSourcePage': 1,
        },
      ]),
      isFalse,
    );
    expect(
      shouldRestorePdfPageBackgrounds(<Map<String, Object?>>[
        <String, Object?>{
          'strokes': <Object?>[
            <String, Object?>{'id': 'handwriting'},
          ],
        },
      ]),
      isFalse,
    );
  });

  test('restores PDF backgrounds when only some pages have images', () {
    expect(
      shouldRestorePdfPageBackgrounds(<Map<String, Object?>>[
        <String, Object?>{
          'pdfSourceName': 'worksheet.pdf',
          'pdfSourcePage': 1,
          'backgroundImage': 'valid-page-1',
          'strokes': <Object?>[],
        },
        <String, Object?>{
          'pdfSourceName': 'worksheet.pdf',
          'pdfSourcePage': 2,
          'backgroundImage': '',
          'strokes': <Object?>[
            <String, Object?>{'id': 'saved-mark'},
          ],
        },
      ]),
      isTrue,
      reason: 'A valid first page must not mask a missing second page.',
    );
  });

  test('merges saved annotations over a freshly rendered PDF page', () {
    final merged = mergeSavedAnnotationsWithPdfPages(
      savedPages: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'saved-page',
          'strokes': <Object?>['annotation'],
          'backgroundImage': 'stale-or-empty',
          'pdfSourceName': 'old.pdf',
        },
      ],
      renderedPages: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'rendered-page',
          'strokes': <Object?>[],
          'backgroundImage': 'fresh-pdf-raster',
          'pdfSourceName': 'worksheet.pdf',
          'pdfSourcePage': 1,
          'pageAspectRatio': .7,
        },
        <String, Object?>{
          'id': 'second-page',
          'backgroundImage': 'second-raster',
          'pdfSourceName': 'worksheet.pdf',
          'pdfSourcePage': 2,
        },
      ],
    );

    expect(merged, hasLength(2));
    expect(merged.first['id'], 'saved-page');
    expect(merged.first['backgroundImage'], 'fresh-pdf-raster');
    expect(merged.first['pdfSourceName'], 'worksheet.pdf');
    expect(merged.first['strokes'], <Object?>['annotation']);
    expect(merged.last['backgroundImage'], 'second-raster');
  });

  test('retains user pages after the rendered PDF recovery limit', () {
    final merged = mergeSavedAnnotationsWithPdfPages(
      savedPages: <Map<String, Object?>>[
        <String, Object?>{
          'pdfSourceName': 'long.pdf',
          'pdfSourcePage': 1,
          'backgroundImage': 'old-1',
          'strokes': <Object?>[],
        },
        <String, Object?>{
          'id': 'inserted-page-after-pdf',
          'template': 'ruled',
          'strokes': <Object?>['user-annotation'],
        },
      ],
      renderedPages: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'rendered-1',
          'pdfSourceName': 'long.pdf',
          'pdfSourcePage': 1,
          'backgroundImage': 'fresh-1',
          'strokes': <Object?>[],
        },
      ],
    );

    expect(merged, hasLength(2));
    expect(merged.first['backgroundImage'], 'fresh-1');
    expect(merged.last['id'], 'inserted-page-after-pdf');
    expect(merged.last['strokes'], <Object?>['user-annotation']);
  });

  test('does not treat envelope-only note metadata as a page', () {
    expect(
      legacyPageFromNoteContent(<String, Object?>{
        'version': 5,
        'coverColor': 0xffffffff,
        'coverIcon': 'book',
        'coverKey': null,
        'text_delta': <Object?>[],
      }),
      isNull,
    );
  });
}
