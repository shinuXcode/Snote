import 'dart:convert';

import 'package:crypto/crypto.dart';

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
/// True when an imported PDF needs its page backgrounds restored.
///
/// Older beta builds could persist a non-empty placeholder raster. Checking
/// only whether `backgroundImage` is a non-empty string makes those pages
/// look restored forever. New pages therefore carry both a PDF source hash
/// and a hash of the raster bytes. A stale/missing fingerprint triggers a
/// render from the original attachment; saved annotations remain preserved.
bool shouldRestorePdfPageBackgrounds(
  List<Map<String, Object?>> pages, {
  String? sourceHash,
}) {
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

  bool hasVerifiedBackground(Map<String, Object?> page) {
    if (page['pdfLazyRender'] == true) {
      final assetId = page['pdfSourceAssetId'];
      final sourcePage = page['pdfSourcePage'];
      return (sourceHash == null || page['pdfSourceHash'] == sourceHash) &&
          assetId is String && assetId.isNotEmpty &&
          sourcePage is num && sourcePage.toInt() > 0;
    }
    if (!hasBackground(page)) return false;
    if (sourceHash == null) return true;
    if (page['pdfSourceHash'] != sourceHash) return false;

    final expectedRasterHash = page['pdfBackgroundHash'];
    if (expectedRasterHash is! String || expectedRasterHash.isEmpty) {
      return false;
    }

    try {
      final bytes = base64Decode(page['backgroundImage']! as String);
      return bytes.isNotEmpty &&
          sha256.convert(bytes).toString() == expectedRasterHash;
    } catch (_) {
      return false;
    }
  }

  final pdfPages = pages.where(hasPdfMetadata).toList(growable: false);
  if (pdfPages.isNotEmpty) {
    // A note can contain pages from multiple imported PDFs. Verify only pages
    // belonging to the current source; never replace another PDF's page set.
    final scopedPages = sourceHash == null
        ? pdfPages
        : pdfPages.where((page) =>
            page['pdfSourceHash'] == null || page['pdfSourceHash'] == sourceHash).toList(growable: false);
    if (scopedPages.isEmpty) return false;
    return scopedPages.any((page) => !hasVerifiedBackground(page));
  }

  bool emptyList(Object? value) => value is! List || value.isEmpty;
  final hasUserContent = pages.any((page) =>
      !emptyList(page['strokes']) ||
      !emptyList(page['images']) ||
      !emptyList(page['textBoxes']));

  // Old PDF page records did not always have per-page source metadata. If the
  // linked PDF is available and pages are otherwise empty, do not trust a
  // legacy raster of unknown origin.
  if (sourceHash != null && !hasUserContent) {
    return pages.any((page) => !hasVerifiedBackground(page));
  }

  // For non-PDF notes, retain legitimate image backgrounds and user content.
  if (pages.any(hasBackground)) return false;
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
  if (renderedPages.isEmpty) {
    return savedPages.map((page) => Map<String, Object?>.from(page)).toList();
  }

  final source = renderedPages.first;
  bool sameSource(Map<String, Object?> saved) {
    final sourceAsset = source['pdfSourceAssetId']?.toString() ?? '';
    final savedAsset = saved['pdfSourceAssetId']?.toString() ?? '';
    if (sourceAsset.isNotEmpty && savedAsset.isNotEmpty) {
      return sourceAsset == savedAsset;
    }
    final sourceHash = source['pdfSourceHash']?.toString() ?? '';
    final savedHash = saved['pdfSourceHash']?.toString() ?? '';
    if (sourceHash.isNotEmpty && savedHash.isNotEmpty) {
      return sourceHash == savedHash;
    }
    final sourceName = source['pdfSourceName']?.toString() ?? '';
    final savedName = saved['pdfSourceName']?.toString() ?? '';
    return sourceName.isNotEmpty && sourceName == savedName;
  }

  final matchingIndices = <int>[];
  final savedByPageNumber = <int, Map<String, Object?>>{};
  for (var index = 0; index < savedPages.length; index++) {
    final saved = savedPages[index];
    final pageNumber = (saved['pdfSourcePage'] as num?)?.toInt();
    if (!sameSource(saved) || pageNumber == null || pageNumber <= 0) continue;
    matchingIndices.add(index);
    savedByPageNumber[pageNumber] = saved;
  }

  final refreshedPages = <Map<String, Object?>>[];
  for (final record in renderedPages) {
    final rendered = Map<String, Object?>.from(record);
    final pageNumber = (record['pdfSourcePage'] as num?)?.toInt();
    final saved = pageNumber == null ? null : savedByPageNumber[pageNumber];
    if (saved != null) {
      rendered.addAll(saved);
      rendered['id'] = saved['id'] ?? record['id'];
      for (final key in const [
        'pdfLazyRender',
        'pdfSourceAssetId',
        'pdfSourceName',
        'pdfSourcePage',
        'pdfSourceHash',
        'pdfBackgroundHash',
        'pageAspectRatio',
      ]) {
        if (record.containsKey(key)) {
          rendered[key] = record[key];
        } else {
          rendered.remove(key);
        }
      }
      // Keep annotations from the saved page but never keep a stale raster
      // when the refreshed page is represented by a lazy source reference.
      if (record['pdfLazyRender'] == true) {
        rendered.remove('backgroundImage');
        rendered.remove('pdfBackgroundHash');
      } else {
        if (record.containsKey('backgroundImage')) {
          rendered['backgroundImage'] = record['backgroundImage'];
        } else {
          rendered.remove('backgroundImage');
        }
      }
    }
    refreshedPages.add(rendered);
  }

  if (matchingIndices.isEmpty) {
    final hasStablePdfPageIdentity = savedPages.any((page) =>
        page['pdfSourcePage'] is num &&
        ((page['pdfSourceAssetId'] is String && (page['pdfSourceAssetId'] as String).isNotEmpty) ||
            (page['pdfSourceHash'] is String && (page['pdfSourceHash'] as String).isNotEmpty) ||
            (page['pdfSourceName'] is String && (page['pdfSourceName'] as String).isNotEmpty)));
    if (hasStablePdfPageIdentity) {
      // Another identified PDF is already in this note. Keep it and append
      // the new source rather than overlaying the wrong source's annotations.
      return <Map<String, Object?>>[
        ...savedPages.map((page) => Map<String, Object?>.from(page)),
        ...refreshedPages,
      ];
    }

    // Legacy notebooks often have blank page placeholders or page records
    // without a source-page number. Keep old index-based recovery semantics
    // only for these ambiguous records, and preserve their annotations.
    final positional = <Map<String, Object?>>[];
    for (var index = 0; index < refreshedPages.length; index++) {
      final rendered = Map<String, Object?>.from(refreshedPages[index]);
      if (index < savedPages.length) {
        final saved = savedPages[index];
        rendered.addAll(saved);
        rendered['id'] = saved['id'] ?? refreshedPages[index]['id'];
        for (final key in const [
          'pdfLazyRender', 'pdfSourceAssetId', 'pdfSourceName',
          'pdfSourcePage', 'pdfSourceHash', 'pdfBackgroundHash',
          'pageAspectRatio',
        ]) {
          if (refreshedPages[index].containsKey(key)) {
            rendered[key] = refreshedPages[index][key];
          } else {
            rendered.remove(key);
          }
        }
        if (refreshedPages[index]['pdfLazyRender'] == true) {
          rendered.remove('backgroundImage');
          rendered.remove('pdfBackgroundHash');
        } else if (refreshedPages[index].containsKey('backgroundImage')) {
          rendered['backgroundImage'] = refreshedPages[index]['backgroundImage'];
        } else {
          rendered.remove('backgroundImage');
        }
        rendered['strokes'] = saved['strokes'] ?? refreshedPages[index]['strokes'];
        rendered['images'] = saved['images'] ?? refreshedPages[index]['images'];
        rendered['textBoxes'] = saved['textBoxes'] ?? refreshedPages[index]['textBoxes'];
      }
      positional.add(rendered);
    }
    if (savedPages.length > refreshedPages.length) {
      positional.addAll(savedPages.skip(refreshedPages.length).map(
        (page) => Map<String, Object?>.from(page),
      ));
    }
    return positional;
  }

  final firstMatch = matchingIndices.first;
  final matchingSet = matchingIndices.toSet();
  final merged = <Map<String, Object?>>[];
  for (var index = 0; index < savedPages.length; index++) {
    if (index == firstMatch) merged.addAll(refreshedPages);
    if (matchingSet.contains(index)) continue;
    merged.add(Map<String, Object?>.from(savedPages[index]));
  }
  return merged;
}

/// Keeps page navigation inside the available document range.
///
/// A stale index may survive page deletion, session restoration, or an older
/// document state. Clamp it before painting instead of rendering a spinner
/// forever while the index remains invalid.
int clampNotePageIndex(int index, int pageCount) {
  if (pageCount <= 0) return 0;
  return index.clamp(0, pageCount - 1).toInt();
}
