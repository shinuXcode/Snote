/// Restores notebook pages written by early Snote builds that stored a
/// single page directly in content_json instead of wrapping it in `pages`.
///
/// Returns null for envelope-only note content so callers can safely create a
/// normal blank page for genuinely empty notes. This helper never mutates input.
Map<String, Object?>? legacyPageFromNoteContent(Map<String, Object?> content) {
  const pageKeys = <String>{
    'strokes',
    'images',
    'textBoxes',
    'backgroundImage',
    'pdfSourceName',
    'pdfSourcePage',
    'template',
    'pageSize',
    'pageAspectRatio',
    'orientation',
    'paperColor',
    'lineColor',
    'lineOpacity',
    'spacing',
    'lineWidth',
    'cornellAssist',
  };

  if (!pageKeys.any(content.containsKey)) return null;
  return Map<String, Object?>.from(content);
}

/// Restores the editor mode where possible. Earlier releases did not persist
/// the handwriting/text toggle, so infer text mode only for text-only notes.
bool? restoreNoteDrawMode({
  required Object? savedMode,
  required Object? textDelta,
  required bool hasVisibleCanvasContent,
}) {
  if (savedMode == 'handwriting') return true;
  if (savedMode == 'text') return false;
  if (hasVisibleCanvasContent || textDelta is! List) return null;

  for (final operation in textDelta) {
    if (operation is! Map) continue;
    final insert = operation['insert'];
    if (insert is String && insert.replaceAll('\n', '').trim().isNotEmpty) {
      return false;
    }
    if (insert is Map) return false;
  }
  return null;
}
