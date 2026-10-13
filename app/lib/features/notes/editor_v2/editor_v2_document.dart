import 'dart:convert';

import '../note_content_compatibility.dart';

/// Compatibility-first document codec for the rebuilt editor.
///
/// The editor intentionally keeps Snote's existing page envelope and stroke
/// serialization. This lets the new input/rendering pipeline open and save
/// existing notebooks without rewriting or discarding unknown metadata.
class EditorV2DocumentCodec {
  const EditorV2DocumentCodec._();

  static Map<String, Object?> decodeRoot(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
    final Object? value;
    try {
      value = jsonDecode(raw);
    } on FormatException catch (error) {
      throw FormatException('Saved note content is not valid JSON: ${error.message}');
    }
    if (value is! Map) {
      throw const FormatException('Saved note content must be a JSON object.');
    }
    return value.map<String, Object?>((key, value) =>
        MapEntry<String, Object?>(key.toString(), value));
  }

  static List<Map<String, Object?>> decodePages(
    Map<String, Object?> root,
  ) {
    final raw = root['pages'];
    final pages = <Map<String, Object?>>[];
    if (raw != null && raw is! List) {
      throw const FormatException('Saved notebook pages have an unsupported format.');
    }
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map) {
          throw FormatException('Saved notebook page ${i + 1} is malformed.');
        }
        pages.add(normalizePage(item.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        )));
      }
      if (raw.isNotEmpty && pages.isEmpty) {
        throw const FormatException('No notebook pages could be restored.');
      }
    }

    if (pages.isEmpty) {
      final legacy = legacyPageFromNoteContent(root);
      if (legacy != null) pages.add(normalizePage(legacy));
    }
    return pages;
  }

  static Map<String, Object?> normalizePage(
    Map<String, Object?> source, {
    String? fallbackId,
  }) {
    final page = Map<String, Object?>.from(source);
    page['id'] ??= fallbackId ?? DateTime.now().microsecondsSinceEpoch.toString();
    page['template'] ??= 'dotted';
    page['paperColor'] ??= 0xffffffff;
    page['lineColor'] ??= 0xffd8dee8;
    page['lineOpacity'] ??= .85;
    page['spacing'] ??= 28.0;
    page['lineWidth'] ??= .7;
    page['pageSize'] ??= 'A4';
    page['cornellAssist'] ??= false;
    page['orientation'] ??= 'vertical';

    final strokes = page['strokes'];
    if (strokes is Map && strokes['strokes'] is List) {
      page['strokes'] = List<Object?>.from(strokes['strokes'] as List);
    } else if (strokes == null) {
      page['strokes'] = <Object?>[];
    } else if (strokes is! List) {
      throw const FormatException('A page contains strokes in an unsupported format.');
    }

    for (final key in const ['images', 'textBoxes']) {
      final value = page[key];
      if (value == null) {
        page[key] = <Object?>[];
      } else if (value is! List) {
        throw FormatException('A page contains an invalid $key collection.');
      }
    }
    return page;
  }

  static Map<String, Object?> savePayload({
    required Map<String, Object?> previousContent,
    required List<Map<String, Object?>> pages,
    required String editorMode,
    List<int>? bookmarkedPages,
    required List<dynamic> textDelta,
    required int currentPageIndex,
  }) {
    final result = Map<String, Object?>.from(previousContent);
    result['version'] = 6;
    result['editorEngineVersion'] = 2;
    result['editorMode'] = editorMode;
    result['text_delta'] = textDelta;
    result['currentPageIndex'] = currentPageIndex;
    result['pages'] = pages
        .map((page) => Map<String, Object?>.from(page))
        .toList(growable: false);
    if (bookmarkedPages != null) {
      result['bookmarkedPages'] = bookmarkedPages.toList(growable: false);
    }
    // Existing title-cover metadata, rich-text delta, attachments, and any
    // future fields are retained because the original envelope is copied.
    return result;
  }

  static int clampPage(int index, int pageCount) {
    if (pageCount <= 0) return 0;
    return index.clamp(0, pageCount - 1).toInt();
  }

  static List<Map<String, Object?>> clonePages(
    List<Map<String, Object?>> pages,
  ) {
    final decoded = jsonDecode(jsonEncode(pages));
    if (decoded is! List) {
      throw const FormatException('Could not snapshot the notebook pages.');
    }
    return decoded
        .whereType<Map>()
        .map((item) => item.map<String, Object?>(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .toList(growable: true);
  }
}
