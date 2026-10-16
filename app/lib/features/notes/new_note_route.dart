import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';
import 'note_editor_page.dart';

/// Dedicated full-screen New Note route.
///
/// Use Snote's feature-complete editor until the replacement editor has passed
/// runtime layout and touch-input checks on physical Android hardware. Keeping
/// this route full-screen avoids mounting a second Scaffold inside the notebook
/// workspace, which previously caused missing or clipped editor layouts.
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
      ),
    );
  }
}
