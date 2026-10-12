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
