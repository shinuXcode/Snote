import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';
import 'nextgen_editor_route.dart';

/// Dedicated full-screen entry to Beta 79's separate editor route and engine.
/// The route does not mount the legacy NoteEditorPage or SnoteCanvas pipeline.
class NewNoteRoute extends StatelessWidget {
  final LocalNote note;

  const NewNoteRoute({super.key, required this.note});

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[Snote][Beta79][NewNote] route noteId=${note.id} '
      'viewport=${MediaQuery.sizeOf(context).width}x'
      '${MediaQuery.sizeOf(context).height}',
    );
    return SnoteNextEditorRoute(
      key: ValueKey<String>('beta79-new-note-route-${note.id}'),
      note: note,
    );
  }
}
