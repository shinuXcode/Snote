import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/data/local/note_repository.dart';
import 'package:snote/features/notes/new_note_route.dart';
import 'package:snote/features/notes/note_editor_page.dart';

void main() {
  testWidgets(
    'New Note route mounts the feature-complete full-screen editor shell',
    (tester) async {
      final note = LocalNote(
        id: 'widget-smoke-note',
        title: 'New Note route smoke test',
        folderId: null,
        noteType: 'handwriting',
        contentJson: null,
        createdAt: 1,
        updatedAt: 1,
        version: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: NewNoteRoute(note: note),
        ),
      );

      // The editor must provide a visible app bar immediately, even while
      // asynchronous local-database restoration is still in progress.
      expect(find.byType(NoteEditorPage), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('New Note route smoke test'), findsOneWidget);
    },
  );
}
