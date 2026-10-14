import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/notes/workspace_layout.dart';

void main() {
  group('usesSplitNoteWorkspace', () {
    test('Android tablets always open the editor full-screen', () {
      expect(
        usesSplitNoteWorkspace(platform: TargetPlatform.android, width: 1536),
        isFalse,
      );
    });

    test('iPad-sized layouts use full-screen editor navigation', () {
      expect(
        usesSplitNoteWorkspace(platform: TargetPlatform.iOS, width: 1366),
        isFalse,
      );
    });

    test('wide desktop layouts retain the split workspace', () {
      expect(
        usesSplitNoteWorkspace(platform: TargetPlatform.windows, width: 1536),
        isTrue,
      );
      expect(
        usesSplitNoteWorkspace(platform: TargetPlatform.linux, width: 1200),
        isTrue,
      );
    });

    test('narrow desktop layouts use full-screen editor navigation', () {
      expect(
        usesSplitNoteWorkspace(platform: TargetPlatform.windows, width: 1119),
        isFalse,
      );
    });
  });
}
