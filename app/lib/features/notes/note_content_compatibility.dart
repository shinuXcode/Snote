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

  bool hasPdfMetadata(Map<String, Object?> page) {
    final source = page['pdfSourceName'];
    final index = page['pdfSourcePage'];
    return (source is String && source.isNotEmpty) || index is num;
  }

  bool hasBackground(Map<String, Object?> page) {
    final image = page['backgroundImage'];
    return image is String && image.isNotEmpty;
  }

  // Restore partial imports too. Earlier code returned false as soon as it
  // found ONE valid background, even when other PDF pages were still blank.
  final pdfPages = pages.where(hasPdfMetadata).toList(growable: false);
  if (pdfPages.isNotEmpty) {
    return pdfPages.any((page) => !hasBackground(page));
  }

  // Some early imports did not persist per-page PDF metadata. In that legacy
  // shape, only recover when the saved pages are all visually empty.
  if (pages.any(hasBackground)) return false;

  bool emptyList(Object? value) => value is! List || value.isEmpty;
  return pages.every((page) =>
      emptyList(page['strokes']) &&
      emptyList(page['images']) &&
      emptyList(page['textBoxes']) &&
      !hasBackground(page));
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

  // The renderer intentionally caps PDF snapshots for performance. Preserve
  // any user-created pages and annotations after the rendered range rather
  // than dropping them during a recovery pass.
  if (savedPages.length > renderedPages.length) {
    merged.addAll(
      savedPages
          .skip(renderedPages.length)
          .map((page) => Map<String, Object?>.from(page)),
    );
  }
  return merged;
}

