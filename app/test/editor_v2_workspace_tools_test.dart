import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/widgets/page_background.dart';

void main() {
  test('shape catalogue exposes more than 200 tool choices', () {
    expect(CanvasTool.values.length, greaterThanOrEqualTo(200));
    expect(CanvasTool.octagon.isShape, isTrue);
    expect(CanvasTool.matrixGrid.isShape, isTrue);
    expect(CanvasTool.virusIcon.isShape, isTrue);
  });

  test('dotted page background redraws when opacity or spacing changes', () {
    const original = PageBackground(
      template: PageTemplate.dotted,
      spacing: 28,
      lineOpacity: .85,
    );
    const same = PageBackground(
      template: PageTemplate.dotted,
      spacing: 28,
      lineOpacity: .85,
    );
    const changed = PageBackground(
      template: PageTemplate.dotted,
      spacing: 36,
      lineOpacity: .6,
    );

    expect(original.shouldRepaint(same), isFalse);
    expect(original.shouldRepaint(changed), isTrue);
  });
}
