import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/ui/snote_tool_glyph.dart';

void main() {
  testWidgets('writing tool glyphs render as background-free vector icons', (tester) async {
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
      MaterialApp(
        home: Scaffold(
          body: Wrap(
            children: tools
                .map((tool) => SnoteToolGlyph(
                      tool: tool,
                      color: Colors.black,
                      size: 24,
                    ))
                .toList(),
          ),
        ),
      ),
    );

    expect(find.byType(SnoteToolGlyph), findsNWidgets(tools.length));
    expect(find.byType(CustomPaint), findsNWidgets(tools.length));
  });
}
