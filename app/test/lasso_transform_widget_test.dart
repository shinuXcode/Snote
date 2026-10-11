import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/models/stroke.dart';
import 'package:snote/canvas_engine/models/stroke_codec.dart';
import 'package:snote/canvas_engine/widgets/snote_canvas.dart';
import 'package:snote/canvas_engine/widgets/snote_canvas_controller.dart';

const _pen = PenConfig(
  type: PenType.ballpoint,
  color: Color(0xff202020),
  size: 4,
);

Stroke _sampleStroke() => const Stroke(
      id: 'sample-stroke',
      points: [
        StrokePoint(position: Offset(40, 40), pressure: .6),
        StrokePoint(position: Offset(80, 80), pressure: .8),
      ],
      pen: _pen,
    );

Future<(SnoteCanvasController, Rect)> _mountCanvas(WidgetTester tester) async {
  final controller = SnoteCanvasController();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: SnoteCanvas(
              pen: _pen,
              tool: CanvasTool.lasso,
              controller: controller,
              initialDocument: StrokeCodec.strokesToDocument([_sampleStroke()]),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (controller, tester.getRect(find.byType(SnoteCanvas)));
}

Future<void> _lassoSample(WidgetTester tester, Rect canvasRect) async {
  final points = <Offset>[
    const Offset(20, 20),
    const Offset(100, 20),
    const Offset(100, 100),
    const Offset(20, 100),
    const Offset(20, 20),
  ];
  final gesture = await tester.startGesture(
    canvasRect.topLeft + points.first,
    kind: PointerDeviceKind.stylus,
  );
  for (final point in points.skip(1)) {
    await gesture.moveTo(canvasRect.topLeft + point);
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('lasso-selected strokes can be dragged to a new location', (tester) async {
    final (controller, rect) = await _mountCanvas(tester);
    await _lassoSample(tester, rect);
    expect(controller.selectionCount, 1);

    final gesture = await tester.startGesture(
      rect.topLeft + const Offset(60, 60),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(rect.topLeft + const Offset(100, 120));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final moved = controller.strokes.single;
    expect(moved.points.first.position, const Offset(80, 100));
    expect(moved.points.last.position, const Offset(120, 140));
    controller.dispose();
  });

  testWidgets('lasso corner handles resize vector strokes without losing their points', (tester) async {
    final (controller, rect) = await _mountCanvas(tester);
    await _lassoSample(tester, rect);
    expect(controller.selectionCount, 1);

    final gesture = await tester.startGesture(
      rect.topLeft + const Offset(80, 80),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(rect.topLeft + const Offset(120, 120));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final resized = controller.strokes.single;
    expect(resized.points.first.position, const Offset(40, 40));
    expect(resized.points.last.position, const Offset(120, 120));
    controller.dispose();
  });

  testWidgets('lasso side handles resize one axis like a crop tool', (tester) async {
    final (controller, rect) = await _mountCanvas(tester);
    await _lassoSample(tester, rect);
    expect(controller.selectionCount, 1);

    final gesture = await tester.startGesture(
      rect.topLeft + const Offset(80, 60),
      kind: PointerDeviceKind.stylus,
    );
    await gesture.moveTo(rect.topLeft + const Offset(120, 60));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    final resized = controller.strokes.single;
    expect(resized.points.first.position, const Offset(40, 40));
    expect(resized.points.last.position, const Offset(120, 80));
    controller.dispose();
  });

  testWidgets('duplicate option creates a separately movable selected copy', (tester) async {
    final (controller, rect) = await _mountCanvas(tester);
    await _lassoSample(tester, rect);
    controller.duplicateSelection();
    await tester.pump();

    expect(controller.strokes, hasLength(2));
    expect(controller.selectionCount, 1);
    expect(controller.strokes.last.points.first.position, const Offset(58, 58));
    controller.dispose();
  });
}
