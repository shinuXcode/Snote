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
