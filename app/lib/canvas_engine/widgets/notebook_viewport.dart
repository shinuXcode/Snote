import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;
import '../input/viewport_transform.dart';

class NotebookViewport extends StatefulWidget {
  final Widget child;
  final bool allowSingleFingerPan;
  final double minScale;
  final double maxScale;

  const NotebookViewport({
    super.key,
    required this.child,
    this.allowSingleFingerPan = false,
    this.minScale = .5,
    this.maxScale = 4,
  });

  @override
  State<NotebookViewport> createState() => _NotebookViewportState();
}

class _NotebookViewportState extends State<NotebookViewport> {
  ViewportTransform _transform = const ViewportTransform();
  int _touchCount = 0;
  late ViewportTransform _gestureStart;
  Offset _gestureDocumentFocal = Offset.zero;

  void _down(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.trackpad) {
      _touchCount++;
    }
  }

  void _up(PointerEvent event) {
    if (event.kind == PointerDeviceKind.touch ||
        event.kind == PointerDeviceKind.trackpad) {
      _touchCount = (_touchCount - 1).clamp(0, 20).toInt();
    }
  }

  bool get _gestureAllowed =>
      widget.allowSingleFingerPan || _touchCount >= 2;

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _transform;
    _gestureDocumentFocal =
        _transform.toDocument(details.focalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_gestureAllowed) return;
    final nextScale =
        (_gestureStart.scale * details.scale)
            .clamp(widget.minScale, widget.maxScale)
            .toDouble();
    final nextPan = details.focalPoint -
        Offset(
          _gestureDocumentFocal.dx * nextScale,
          _gestureDocumentFocal.dy * nextScale,
        );

    setState(() {
      _transform = _gestureStart.copyWith(
        scale: nextScale,
        pan: nextPan,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.trackpad,
        },
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: ClipRect(
          child: Transform(
            alignment: Alignment.topLeft,
            transform: Matrix4.identity()
              ..translate(
                _transform.pan.dx,
                _transform.pan.dy,
              )
              ..scale(
                _transform.scale,
                _transform.scale,
              ),
            transformHitTests: true,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
