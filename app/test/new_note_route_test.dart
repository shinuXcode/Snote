import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/data/local/note_repository.dart';
import 'package:snote/features/notes/new_note_route.dart';
import 'package:snote/features/notes/editor_v2/editor_v2_page.dart';

void main() {
  testWidgets(
    'New Note route mounts the separate Beta 79 editor engine and full-screen shell',
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

      // The editor shell must be present immediately, with a visible body
      // while local storage restores the note. This catches the old blank-route
      // regression, which the earlier app-bar-only assertion did not detect.
      expect(find.byType(EditorV2Page), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('New Note route smoke test'), findsOneWidget);
      expect(find.text('Preparing your note…'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Allow storage initialization either to finish or to display the
      // explicit recovery state; neither path may collapse into a blank body.
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      final hasPageSurface = find
          .byKey(const ValueKey<String>('editor-v2-page-surface'))
          .evaluate()
          .isNotEmpty;
      final hasLoadingState = find.text('Preparing your note…').evaluate().isNotEmpty;
      final hasRecoveryState = find.text('Could not render this note').evaluate().isNotEmpty;
      expect(
        hasPageSurface || hasLoadingState || hasRecoveryState,
        isTrue,
        reason: 'New Note must show a page, a loading state, or a visible recovery message.',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
