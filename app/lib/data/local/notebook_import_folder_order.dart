/// Returns imported folders in parent-first order while preserving input data.
///
/// Missing parents are left for the importer to map to its fallback folder.
/// Cyclic parent references are broken by treating one entry as a root, avoiding
/// an infinite loop and ensuring imported content remains accessible.
List<Map<String, Object?>> orderImportedFolders(
  List<Map<String, Object?>> folders,
) {
  final pending = folders
      .map((folder) => Map<String, Object?>.from(folder))
      .toList(growable: true);
  final allIds = pending
      .map((folder) => folder['id']?.toString())
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toSet();
  final resolvedIds = <String>{};
  final ordered = <Map<String, Object?>>[];

  while (pending.isNotEmpty) {
    final readyIndex = pending.indexWhere((folder) {
      final parentId = folder['parentId']?.toString();
      return parentId == null ||
          !allIds.contains(parentId) ||
          resolvedIds.contains(parentId);
    });
    final item = pending.removeAt(readyIndex < 0 ? 0 : readyIndex);
    if (readyIndex < 0) item['parentId'] = null;

    ordered.add(item);
    final id = item['id']?.toString();
    if (id != null && id.isNotEmpty) resolvedIds.add(id);
  }

  return ordered;
}
