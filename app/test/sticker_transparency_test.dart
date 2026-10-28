import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/features/notes/editor_v2/editor_v2_page.dart';

void main() {
  test('sticker and text-box surface remains transparent and borderless', () {
    const decoration = snoteTransparentTextBoxDecoration;
    expect(decoration.color, Colors.transparent);
    expect(decoration.image, isNull);
    final border = decoration.border! as Border;
    expect(border.top.color, Colors.transparent);
    expect(border.right.color, Colors.transparent);
    expect(border.bottom.color, Colors.transparent);
    expect(border.left.color, Colors.transparent);
    expect(border.top.width, 0);
    expect(border.right.width, 0);
    expect(border.bottom.width, 0);
    expect(border.left.width, 0);
  });
}
