import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';
import 'editor_v2/editor_v2_page.dart';

/// Dedicated full-screen New Note entry point for the rebuilt editor.
///
/// Each note receives independent route and editor identities. Repository
/// creation/validation is performed by the home screen before this route is
/// pushed, and EditorV2Page owns document initialization and recovery errors.
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
      child: EditorV2Page(
        key: ValueKey<String>('new-note-editor-v2-${note.id}'),
        note: note,
      ),
    );
  }
}
