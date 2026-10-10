import 'package:flutter/material.dart';

import '../../data/local/folder_repository.dart';

IconData folderIconForKey(String key) {
  switch (key) {
    case 'book':
      return Icons.menu_book_rounded;
    case 'science':
      return Icons.science_rounded;
    case 'math':
      return Icons.functions_rounded;
    case 'star':
      return Icons.star_rounded;
    case 'lightbulb':
      return Icons.lightbulb_rounded;
    case 'work':
      return Icons.work_rounded;
    case 'archive':
      return Icons.archive_rounded;
    default:
      return Icons.folder_rounded;
  }
}

/// Recursive folder browser that supports arbitrary depth and drag-and-drop
/// moves. Repository-level validation remains authoritative for cycle checks.
class FolderTreeView extends StatefulWidget {
  final List<LocalFolder> folders;
  final String? selectedFolderId;
  final ValueChanged<LocalFolder> onSelect;
  final Future<void> Function(String folderId, String? parentId) onMove;
  final ValueChanged<LocalFolder> onRename;
  final ValueChanged<LocalFolder> onDelete;
  final ValueChanged<LocalFolder> onAppearance;

  const FolderTreeView({
    super.key,
    required this.folders,
    required this.selectedFolderId,
    required this.onSelect,
    required this.onMove,
    required this.onRename,
    required this.onDelete,
    required this.onAppearance,
  });

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  final Set<String> _expanded = <String>{};

  @override
  void didUpdateWidget(covariant FolderTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final validIds = widget.folders.map((folder) => folder.id).toSet();
    _expanded.removeWhere((id) => !validIds.contains(id));
  }

  Map<String, LocalFolder> get _byId => {
        for (final folder in widget.folders) folder.id: folder,
      };

  bool _wouldCreateCycle(String draggedId, String? destinationId) {
    if (destinationId == null) return false;
    if (draggedId == destinationId) return true;
    final byId = _byId;
    final seen = <String>{};
    String? current = destinationId;
    while (current != null && seen.add(current)) {
      if (current == draggedId) return true;
      current = byId[current]?.parentId;
    }
    return false;
  }

  Widget _rootDropTarget(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => !_wouldCreateCycle(details.data, null),
      onAcceptWithDetails: (details) => widget.onMove(details.data, null),
      builder: (context, candidates, rejected) => AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: candidates.isNotEmpty
              ? scheme.primaryContainer.withValues(alpha: .75)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: candidates.isNotEmpty
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: const ListTile(
          dense: true,
          leading: Icon(Icons.home_work_outlined),
          title: Text('Move to notebook root'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rootFolders = widget.folders
        .where((folder) => folder.parentId == null)
        .toList()
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rootDropTarget(context),
        if (rootFolders.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Create folders to organize your notes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ...rootFolders.map((folder) => _folderRow(folder, 0)),
      ],
    );
  }

  Widget _folderRow(LocalFolder folder, int depth, [Set<String> ancestry = const <String>{}]) {
    final branch = <String>{...ancestry, folder.id};
    final children = widget.folders
        .where((candidate) => candidate.parentId == folder.id && !branch.contains(candidate.id))
        .toList()
      ..sort((a, b) {
        final order = a.sortOrder.compareTo(b.sortOrder);
        return order != 0 ? order : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    final hasChildren = children.isNotEmpty;
    final expanded = _expanded.contains(folder.id);
    final selected = widget.selectedFolderId == folder.id;
    final theme = Theme.of(context);
    final folderColor = Color(folder.colorValue);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          !_wouldCreateCycle(details.data, folder.id),
      onAcceptWithDetails: (details) =>
          widget.onMove(details.data, folder.id),
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        final tile = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: EdgeInsets.only(left: depth * 14.0, bottom: 2),
          decoration: BoxDecoration(
            color: hovering
                ? theme.colorScheme.primaryContainer
                : selected
                    ? theme.colorScheme.secondaryContainer.withValues(alpha: .7)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: hovering
                ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                : null,
          ),
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -1),
            selected: selected,
            contentPadding: const EdgeInsets.only(left: 2, right: 4),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasChildren)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => setState(() {
                      if (expanded) {
                        _expanded.remove(folder.id);
                      } else {
                        _expanded.add(folder.id);
                      }
                    }),
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.chevron_right_rounded,
                      size: 20,
                    ),
                  )
                else
                  const SizedBox(width: 20),
                Icon(folderIconForKey(folder.iconKey), color: folderColor, size: 20),
              ],
            ),
            title: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
            onTap: () {
              if (hasChildren) setState(() => _expanded.add(folder.id));
              widget.onSelect(folder);
            },
            trailing: PopupMenuButton<String>(
              tooltip: 'Folder actions',
              onSelected: (value) {
                if (value == 'appearance') {
                  widget.onAppearance(folder);
                } else if (value == 'rename') {
                  widget.onRename(folder);
                } else if (value == 'delete') {
                  widget.onDelete(folder);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'appearance', child: Text('Color and icon')),
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete folder')),
              ],
            ),
          ),
        );

        return LongPressDraggable<String>(
          data: folder.id,
          feedback: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Card(
                child: ListTile(
                  leading: Icon(folderIconForKey(folder.iconKey), color: folderColor),
                  title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: .28, child: tile),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile,
              if (expanded && hasChildren)
                ...children.map((child) => _folderRow(child, depth + 1, branch)),
            ],
          ),
        );
      },
    );
  }
}
