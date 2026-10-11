import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/features/folders/folder_cover_art.dart';

void main() {
  testWidgets('the built-in cover catalog renders all 100 cover variants', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 330,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var index = 0; index < 100; index++)
                    SizedBox(
                      width: 58,
                      height: 82,
                      child: FolderCoverArt(
                        coverKey: 'cover:' + index.toString(),
                        title: 'Cover ' + (index + 1).toString(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Cover 1'), findsOneWidget);
    expect(find.text('Cover 100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
