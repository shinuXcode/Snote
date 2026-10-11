import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/models/stroke.dart';
import 'package:snote/canvas_engine/painters/canvas_painter.dart';

void main() {
  const subjectShapes = <CanvasTool>[
    CanvasTool.mathCoordinateAxes,
    CanvasTool.mathParabola,
    CanvasTool.mathSineWave,
    CanvasTool.mathAngle,
    CanvasTool.mathRightAngle,
    CanvasTool.physicsVector,
    CanvasTool.physicsResistor,
    CanvasTool.physicsCapacitor,
    CanvasTool.physicsBattery,
    CanvasTool.physicsDiode,
    CanvasTool.physicsConvexLens,
    CanvasTool.chemistryBenzene,
    CanvasTool.chemistryMolecule,
    CanvasTool.chemistryAtom,
    CanvasTool.chemistryOrbital,
    CanvasTool.chemistryFlask,
    CanvasTool.chemistryBeaker,
    CanvasTool.biologyCell,
    CanvasTool.biologyMitochondrion,
    CanvasTool.biologyDna,
    CanvasTool.biologyLeaf,
    CanvasTool.biologyNeuron,
  ];

  test('all subject-specific diagram tools are recognized as drawable shapes', () {
    for (final tool in subjectShapes) {
      expect(tool.isShape, isTrue, reason: '${tool.name} must be a drawable shape');
      expect(tool.label.trim(), isNotEmpty, reason: '${tool.name} needs an accessible label');
    }
  });

  test('all subject-specific shapes render without throwing', () {
    for (final tool in subjectShapes) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = SnoteCanvasPainter(
        strokes: [
          Stroke(
            id: tool.name,
            points: const [
              StrokePoint(position: Offset(12, 12), pressure: 1),
              StrokePoint(position: Offset(148, 108), pressure: 1),
            ],
            pen: const PenConfig(
              type: PenType.ballpoint,
              color: Color(0xff2454a6),
              size: 2,
            ),
            shape: tool.name,
          ),
        ],
        activeStroke: null,
        activePoints: const <StrokePoint>[],
        activePen: null,
        activeTool: null,
        activeFill: false,
        activeCustomSides: 6,
        activeStickerText: null,
        selectedIds: const <String>{},
        lassoPath: const <Offset>[],
        drawActive: false,
      );
      expect(
        () => painter.paint(canvas, const Size(160, 120)),
        returnsNormally,
        reason: '${tool.name} should paint a valid diagram',
      );
      recorder.endRecording().dispose();
    }
  });
}
