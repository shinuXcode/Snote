import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/widgets/snote_canvas.dart';
import 'package:snote/canvas_engine/widgets/snote_canvas_controller.dart';
import 'package:snote/canvas_engine/models/stroke_codec.dart';

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
    final image = await tester.runAsync(
      () => boundary.toImage(pixelRatio: 1),
    );
    expect(image, isNotNull);
    final liveImage = image!;
    final pixels = await tester.runAsync(
      () => liveImage.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(pixels, isNotNull);
    final localMidpoint = (start + (end - start) / 2) - boundaryRect.topLeft;
    final x = localMidpoint.dx.round().clamp(0, liveImage.width - 1).toInt();
    final y = localMidpoint.dy.round().clamp(0, liveImage.height - 1).toInt();
    final alphaOffset = (y * liveImage.width + x) * 4 + 3;
    expect(pixels!.getUint8(alphaOffset), greaterThan(0));
    liveImage.dispose();

    await gesture.up();
    await tester.pump();
    expect(commitCount, 1);
  });

  testWidgets('lasso selection can be moved and resized directly by touch',
      (tester) async {
    final controller = SnoteCanvasController();
    final tool = ValueNotifier(CanvasTool.ballpoint);
    Map<String, Object?>? latestDocument;
    const pen = PenConfig(
      type: PenType.ballpoint,
      color: Color(0xff202020),
      size: 3,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<CanvasTool>(
            valueListenable: tool,
            builder: (_, selectedTool, __) => SizedBox.expand(
              child: SnoteCanvas(
                pen: pen,
                tool: selectedTool,
                controller: controller,
                onChanged: (document) => latestDocument = document,
                initialDocument: const <String, Object?>{
                  'strokes': <Object?>[],
                },
              ),
            ),
          ),
        ),
      ),
    );

    final canvasRect = tester.getRect(find.byType(SnoteCanvas));
    Future<void> drawPath(List<Offset> points) async {
      final gesture = await tester.startGesture(
        canvasRect.topLeft + points.first,
        kind: PointerDeviceKind.stylus,
      );
      for (final point in points.skip(1)) {
        await gesture.moveTo(canvasRect.topLeft + point);
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }

    await drawPath(const [Offset(40, 40), Offset(120, 120)]);
    await tester.pump();

    tool.value = CanvasTool.lasso;
    await tester.pump();
    await drawPath(const [
      Offset(25, 25),
      Offset(140, 25),
      Offset(140, 140),
      Offset(25, 140),
      Offset(25, 25),
    ]);
    expect(controller.selectionCount, 1);

    final selectedBeforeMove = StrokeCodec.documentToStrokes(latestDocument!);
    final originalBounds = _testBounds(selectedBeforeMove.single.points);

    final moveGesture = await tester.startGesture(
      canvasRect.topLeft + const Offset(65, 65),
      kind: PointerDeviceKind.touch,
    );
    await moveGesture.moveTo(canvasRect.topLeft + const Offset(85, 80));
    await tester.pump();
    await moveGesture.up();
    await tester.pump();

    final movedStrokes = StrokeCodec.documentToStrokes(latestDocument!);
    final movedBounds = _testBounds(movedStrokes.single.points);
    expect(movedBounds.left, greaterThan(originalBounds.left + 15));
    expect(movedBounds.top, greaterThan(originalBounds.top + 10));

    final resizeStart = Offset(movedBounds.right + 8, movedBounds.center.dy);
    final resizeGesture = await tester.startGesture(
      canvasRect.topLeft + resizeStart,
      kind: PointerDeviceKind.touch,
    );
    await resizeGesture.moveTo(
      canvasRect.topLeft + resizeStart + const Offset(24, 0),
    );
    await tester.pump();
    await resizeGesture.up();
    await tester.pump();

    final resizedStrokes = StrokeCodec.documentToStrokes(latestDocument!);
    final resizedBounds = _testBounds(resizedStrokes.single.points);
    expect(resizedBounds.width, greaterThan(movedBounds.width + 8));
    controller.dispose();
    tool.dispose();
  });
}

Rect _testBounds(List<StrokePoint> points) {
  var left = points.first.position.dx;
  var right = left;
  var top = points.first.position.dy;
  var bottom = top;
  for (final point in points.skip(1)) {
    left = left < point.position.dx ? left : point.position.dx;
    right = right > point.position.dx ? right : point.position.dx;
    top = top < point.position.dy ? top : point.position.dy;
    bottom = bottom > point.position.dy ? bottom : point.position.dy;
  }
  return Rect.fromLTRB(left, top, right, bottom);
}
