import 'package:flutter_test/flutter_test.dart';
import 'package:snote/data/local/local_file_store_path.dart';

void main() {
  test('preserves ordinary digits and letters in local file segments', () {
    expect(
      sanitizeLocalFileSegment('folder-0123456789'),
      'folder-0123456789',
    );
    expect(
      sanitizeLocalFileSegment('image-2026-A.png'),
      'image-2026-A.png',
    );
  });

  test('replaces path separators, invalid characters, and control bytes', () {
    expect(
      sanitizeLocalFileSegment('../folder\\bad?.png'),
      '.._folder_bad_.png',
    );
    expect(sanitizeLocalFileSegment('name\u0001file'), 'name_file');
  });

  test('uses a safe fallback for empty segments', () {
    expect(sanitizeLocalFileSegment('  '), 'untitled');
  });
}
