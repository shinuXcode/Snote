import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class WritingGestureLayer extends StatefulWidget {
  final Widget child;
  final VoidCallback onTwoFingerTap;
  final VoidCallback onTwoFingerSwipeUp;

  const WritingGestureLayer({
    super.key,
    required this.child,
    required this.onTwoFingerTap,
    required this.onTwoFingerSwipeUp,
  });

  @override
  State<WritingGestureLayer> createState() => _WritingGestureLayerState();
}

class _WritingGestureLayerState extends State<WritingGestureLayer> {
  final Map<int, Offset> _down = <int, Offset>{};
  final Map<int, Offset> _last = <int, Offset>{};
  DateTime? _started;
  bool _moved = false;

  void _downEvent(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _down[event.pointer] = event.position;
    _last[event.pointer] = event.position;
    if (_down.length == 2) {
      _started = DateTime.now();
      _moved = false;
    }
  }

  void _moveEvent(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _last[event.pointer] = event.position;
    final start = _down[event.pointer];
    if (start != null && _down.length >= 2 && (event.position - start).distance > 28) {
      _moved = true;
    }
  }

  void _upEvent(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _last[event.pointer] = event.position;
    if (_down.length == 2) {
      final duration = _started == null ? const Duration(seconds: 9) : DateTime.now().difference(_started!);
      final avgStart = _down.values.fold<double>(0, (sum, value) => sum + value.dy) / 2;
      final avgEnd = _down.keys.map((id) => _last[id] ?? _down[id]!).fold<double>(0, (sum, value) => sum + value.dy) / 2;
      if (!_moved && duration <= const Duration(milliseconds: 320)) {
        widget.onTwoFingerTap();
      } else if (_moved && avgEnd - avgStart < -150) {
        widget.onTwoFingerSwipeUp();
      }
    }
    _down.remove(event.pointer);
    _last.remove(event.pointer);
    if (_down.length < 2) {
      _started = null;
      _moved = false;
    }
  }

  void _cancelEvent(PointerCancelEvent event) {
    if (event.kind != PointerDeviceKind.touch) return;
    _down.remove(event.pointer);
    _last.remove(event.pointer);
    if (_down.length < 2) {
      _started = null;
      _moved = false;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _downEvent,
        onPointerMove: _moveEvent,
        onPointerUp: _upEvent,
        onPointerCancel: _cancelEvent,
        child: widget.child,
      );
}
