import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';
import 'note_editor_page.dart';

/// Dedicated full-screen entry point for newly-created notes.
///
/// Reuses the production editor engine and its complete toolset, but always
/// mounts it as a fresh route instead of relying on the split-workspace
/// embedded editor. This keeps New Note isolated from the home page's layout
/// and gives the editor a note-specific identity.
class NewNoteRoute extends StatelessWidget {
  final LocalNote note;

  const NewNoteRoute({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[Snote][NewNoteRoute] mount noteId=${note.id} '
      'viewport=${MediaQuery.sizeOf(context).width}x'
      '${MediaQuery.sizeOf(context).height}',
    );

    return KeyedSubtree(
      key: ValueKey<String>('new-note-route-${note.id}'),
      child: NoteEditorPage(
        key: ValueKey<String>('new-note-editor-${note.id}'),
        note: note,
        embedded: false,
      ),
    );
  }
}
