import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/widgets/snote_canvas.dart';

void main() {
  testWidgets('active ink is visible before the stylus is lifted', (tester) async {
    final boundaryKey = GlobalKey();
    var commitCount = 0;
    const pen = PenConfig(
      type: PenType.ballpoint,
      color: Color(0xff111111),
      size: 4,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 180,
                height: 180,
                child: SnoteCanvas(
                  pen: pen,
                  initialDocument: const <String, Object?>{'strokes': <Object?>[]},
                  onChanged: (_) => commitCount++,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final canvasRect = tester.getRect(find.byType(SnoteCanvas));
    final boundaryRect = tester.getRect(find.byKey(boundaryKey));
    final start = canvasRect.topLeft + const Offset(20, 20);
    final end = canvasRect.topLeft + const Offset(100, 60);
    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(end);
    await tester.pump();

    // A stroke must already be rendered on the canvas while the pointer is
    // still down. No document commit/pen-up event has happened yet.
    expect(commitCount, 0);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(pixels, isNotNull);
    final localMidpoint = (start + (end - start) / 2) - boundaryRect.topLeft;
    final x = localMidpoint.dx.round().clamp(0, image.width - 1);
    final y = localMidpoint.dy.round().clamp(0, image.height - 1);
    final alphaOffset = (y * image.width + x) * 4 + 3;
    expect(pixels!.getUint8(alphaOffset), greaterThan(0));
    image.dispose();

    await gesture.up();
    await tester.pump();
    expect(commitCount, 1);
  });
}
