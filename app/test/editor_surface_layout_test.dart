import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/widgets/page_background.dart';
import 'package:snote/canvas_engine/widgets/snote_canvas.dart';

void main() {
  testWidgets(
    'paper painter and handwriting canvas fill the bounded note page',
    (tester) async {
      const pageSize = Size(210, 297);
      await tester.binding.setSurfaceSize(const Size(900, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: pageSize.width,
                height: pageSize.height,
                child: Material(
                  color: Colors.white,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            key: const ValueKey<String>('test-page-background'),
                            painter: const PageBackground(
                              template: PageTemplate.dotted,
                              paperColor: Colors.white,
                              lineColor: Color(0xffd8dee8),
                              spacing: 28,
                              lineOpacity: .85,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: RepaintBoundary(
                          child: SnoteCanvas(
                            key: const ValueKey<String>('test-note-canvas'),
                            pen: PenConfig(
                              type: PenType.ballpoint,
                              color: Color(0xff263238),
                              size: 3,
                            ),
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(const ValueKey<String>('test-page-background'))),
        pageSize,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey<String>('test-note-canvas'))),
        pageSize,
      );
    },
  );
}
