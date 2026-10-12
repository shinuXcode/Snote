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

/// True when a PDF-import note needs its original PDF pages rendered again.
/// Older beta builds could save placeholder pages before the PDF snapshots
/// were persisted, leaving a non-empty `pages` list that bypassed recovery.
bool shouldRestorePdfPageBackgrounds(List<Map<String, Object?>> pages) {
  if (pages.isEmpty) return true;

  final hasAnyBackground = pages.any((page) {
    final image = page['backgroundImage'];
    return image is String && image.isNotEmpty;
  });
  if (hasAnyBackground) return false;

  final hasPdfPageMetadata = pages.any((page) {
    final source = page['pdfSourceName'];
    final index = page['pdfSourcePage'];
    return (source is String && source.isNotEmpty) || index is num;
  });
  if (hasPdfPageMetadata) return true;

  // A stale single blank page must not prevent recovery from a saved PDF
  // attachment. Do not treat a page with handwriting/images/text as empty.
  return pages.every((page) {
    bool emptyList(Object? value) => value is! List || value.isEmpty;
    final background = page['backgroundImage'];
    return emptyList(page['strokes']) &&
        emptyList(page['images']) &&
        emptyList(page['textBoxes']) &&
        (background is! String || background.isEmpty);
  });
}

/// Reattaches saved annotations to freshly rendered PDF page backgrounds.
/// Saved annotations and page identifiers are preserved; the new raster
/// background and source-page metadata always come from the original PDF.
List<Map<String, Object?>> mergeSavedAnnotationsWithPdfPages({
  required List<Map<String, Object?>> savedPages,
  required List<Map<String, Object?>> renderedPages,
}) {
  final merged = <Map<String, Object?>>[];
  for (var index = 0; index < renderedPages.length; index++) {
    final rendered = Map<String, Object?>.from(renderedPages[index]);
    if (index < savedPages.length) {
      final saved = savedPages[index];
      rendered.addAll(saved);
      rendered['backgroundImage'] = renderedPages[index]['backgroundImage'];
      rendered['pdfSourceName'] = renderedPages[index]['pdfSourceName'];
      rendered['pdfSourcePage'] = renderedPages[index]['pdfSourcePage'];
      rendered['pageAspectRatio'] = renderedPages[index]['pageAspectRatio'];
      rendered['id'] = saved['id'] ?? renderedPages[index]['id'];
      rendered['strokes'] = saved['strokes'] ?? renderedPages[index]['strokes'];
      rendered['images'] = saved['images'] ?? renderedPages[index]['images'];
      rendered['textBoxes'] =
          saved['textBoxes'] ?? renderedPages[index]['textBoxes'];
    }
    merged.add(rendered);
  }
  return merged;
}

