import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/input/ink_gesture_policy.dart';

void main() {
  test('finger ink is enabled without enabling single-finger viewport pan', () {
    const policy = InkGesturePolicy();
    expect(policy.allowsFingerInk(), isTrue);
    expect(policy.allowsSingleFingerPan(), isFalse);
    expect(policy.isViewportDevice(PointerDeviceKind.touch), isTrue);
    expect(policy.isStylus(PointerDeviceKind.stylus), isTrue);
  });

  test('finger ink can be disabled for navigation-first surfaces', () {
    const policy = InkGesturePolicy(allowFingerInk: false);
    expect(policy.allowsFingerInk(), isFalse);
  });
}
