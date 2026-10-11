import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/widgets/page_background.dart';

void main() {
  test('every built-in and smart page template paints successfully', () {
    for (final template in PageTemplate.values) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = PageBackground(
        template: template,
        paperColor: const Color(0xfff7f8fb),
        lineColor: const Color(0xffa4adbb),
        spacing: 24,
        lineOpacity: .8,
      );
      expect(
        () => painter.paint(canvas, const Size(300, 420)),
        returnsNormally,
        reason: '${template.name} template should paint',
      );
      recorder.endRecording().dispose();
    }
  });

  test('template changes request an immediate repaint', () {
    const oldPainter = PageBackground(template: PageTemplate.dotted);
    const newPainter = PageBackground(template: PageTemplate.math);
    expect(newPainter.shouldRepaint(oldPainter), isTrue);
  });
}
