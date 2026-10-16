import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/data/local/note_repository.dart';
import '../lib/features/tools/flashcard_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flashcards can be created, flipped, marked known and shuffled', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: FlashcardPage(),
      ),
    );
    await tester.pumpAndSettle();

    final front = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Question / front',
    );
    final back = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Answer / back',
    );

    await tester.enterText(front, 'What is photosynthesis?');
    await tester.enterText(back, 'Plants convert light energy into chemical energy.');
    await tester.tap(find.byTooltip('Add card to deck'));
    await tester.pumpAndSettle();

    expect(find.text('What is photosynthesis?'), findsOneWidget);
    expect(find.text('Card 1 of 1'), findsOneWidget);

    await tester.tap(find.text('Tap card to flip'));
    await tester.pumpAndSettle();
    expect(find.text('ANSWER'), findsOneWidget);
    expect(find.text('Plants convert light energy into chemical energy.'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide card editor'));
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Question / front',
    ), findsNothing);

    await tester.tap(find.text('Mark known'));
    await tester.pumpAndSettle();
    expect(find.text('1 known'), findsOneWidget);
    expect(find.text('Known'), findsOneWidget);
  });

  testWidgets('existing decks load in review mode and allow deleting a card', (tester) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const note = LocalNote(
      id: 'deck-1',
      title: 'Biology cards',
      folderId: null,
      noteType: 'flashcard',
      contentJson: '{"noteType":"flashcard","flashcards":[{"id":"a","front":"Q1","back":"A1"},{"id":"b","front":"Q2","back":"A2"}]}',
      createdAt: 1,
      updatedAt: 1,
      deletedAt: null,
      version: 1,
    );
    await tester.pumpWidget(MaterialApp(home: FlashcardPage(note: note)));
    await tester.pumpAndSettle();

    expect(find.text('Card 1 of 2'), findsOneWidget);
    expect(find.byTooltip('Hide card editor'), findsNothing);
    expect(find.byTooltip('Edit cards'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete current card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete card'));
    await tester.pumpAndSettle();

    expect(find.text('Card 1 of 1'), findsOneWidget);
    expect(find.text('Q1'), findsNothing);
    expect(find.text('Q2'), findsOneWidget);
  });
}
