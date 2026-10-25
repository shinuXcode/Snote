/// Sanitizes one file or directory segment without altering ordinary letters,
/// digits, punctuation, or Unicode text. Path separators and control characters
/// are replaced so a caller cannot escape the local Snote files directory.
String sanitizeLocalFileSegment(String name) {
  final clean = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .trim();
  return clean.isEmpty ? 'untitled' : clean;
}
