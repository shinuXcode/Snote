import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/models/stroke.dart';
import 'package:snote/features/notes/editor_v2/editor_v2_ink_painter.dart';

void main() {
  test('EditorV2InkPainter renders live and committed ink into a page', () async {
    const pen = PenConfig(
      type: PenType.fountain,
      color: Color(0xff1b53a6),
      size: 4,
      opacity: 1,
      pressureSensitivity: .8,
    );
    const committed = Stroke(
      id: 'saved-stroke',
      points: <StrokePoint>[
        StrokePoint(position: Offset(20, 24), pressure: .25, timestamp: 1),
        StrokePoint(position: Offset(65, 58), pressure: .7, timestamp: 2),
        StrokePoint(position: Offset(120, 94), pressure: 1, timestamp: 3),
      ],
      pen: pen,
    );
    const live = Stroke(
      id: 'live-stroke',
      points: <StrokePoint>[
        StrokePoint(position: Offset(20, 120), pressure: .5),
        StrokePoint(position: Offset(160, 180), pressure: .9),
      ],
      pen: pen,
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = EditorV2InkPainter(
      strokes: <Stroke>[committed],
      liveStroke: live,
      selectedStrokeIds: <String>{'saved-stroke'},
    );
    painter.paint(canvas, const Size(220, 220));
    final picture = recorder.endRecording();
    final image = await picture.toImage(220, 220);
    final pixels = await image.toByteData(format: ImageByteFormat.rawRgba);
    expect(pixels, isNotNull);
    var painted = 0;
    for (var index = 3; index < pixels!.lengthInBytes; index += 4) {
      if (pixels.getUint8(index) > 0) painted++;
    }
    expect(painted, greaterThan(0));
    image.dispose();
    picture.dispose();
    painter.dispose();
  });

  test('shape geometry painter draws a recognizable coordinate plane', () async {
    const stroke = Stroke(
      id: 'axes-1',
      points: <StrokePoint>[
        StrokePoint(position: Offset(24, 30)),
        StrokePoint(position: Offset(190, 184)),
      ],
      pen: PenConfig(type: PenType.ballpoint, color: Color(0xff263238), size: 3),
      shape: 'cartesianPlane',
    );
    final recorder = PictureRecorder();
    final painter = EditorV2InkPainter(strokes: const <Stroke>[stroke]);
    painter.paint(Canvas(recorder), const Size(220, 220));
    final picture = recorder.endRecording();
    final image = await picture.toImage(220, 220);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);
    expect(bytes!.lengthInBytes, greaterThan(0));
    image.dispose();
    picture.dispose();
    painter.dispose();
  });
}
