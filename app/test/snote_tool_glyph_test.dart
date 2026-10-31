import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/ui/snote_tool_glyph.dart';

void main() {
  testWidgets('writing tool glyphs render without icon tile backgrounds', (tester) async {
    const tools = <CanvasTool>[
      CanvasTool.ballpoint,
      CanvasTool.fountain,
      CanvasTool.pencil,
      CanvasTool.highlighter,
      CanvasTool.marker,
      CanvasTool.brush,
      CanvasTool.eraser,
      CanvasTool.pixelEraser,
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: [
              for (final tool in tools)
                SnoteToolGlyph(tool: tool, color: Colors.black, size: 24),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SnoteToolGlyph), findsNWidgets(tools.length));
    expect(find.byType(CustomPaint), findsNWidgets(tools.length));
  });
}
