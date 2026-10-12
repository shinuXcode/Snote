import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;
import '../input/viewport_transform.dart';
import '../input/ink_gesture_policy.dart';

class NotebookViewport extends StatefulWidget {
  final Widget child;
  final bool allowSingleFingerPan;
  final double minScale;
  final double maxScale;
  final double initialScale;
  final InkGesturePolicy gesturePolicy;

  const NotebookViewport({
    super.key,
    required this.child,
    this.allowSingleFingerPan = false,
    this.minScale = .5,
    this.maxScale = 4,
    this.initialScale = 1,
    this.gesturePolicy = const InkGesturePolicy(),
  });

  @override
  State<NotebookViewport> createState() => _NotebookViewportState();
}

class _NotebookViewportState extends State<NotebookViewport> {
  late ViewportTransform _transform;

  @override
  void initState() {
    super.initState();
    _transform = ViewportTransform(
      scale: widget.initialScale.clamp(widget.minScale, widget.maxScale).toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant NotebookViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialScale != widget.initialScale ||
        oldWidget.minScale != widget.minScale ||
        oldWidget.maxScale != widget.maxScale) {
      _transform = _transform.copyWith(
        scale: widget.initialScale.clamp(widget.minScale, widget.maxScale).toDouble(),
      );
    }
  }
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
      widget.allowSingleFingerPan ||
      widget.gesturePolicy.allowsSingleFingerPan() ||
      _touchCount >= 2;

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _transform;
    _gestureDocumentFocal =
        _transform.toDocument(details.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_gestureAllowed) return;
    final nextScale =
        (_gestureStart.scale * details.scale)
            .clamp(widget.minScale, widget.maxScale)
            .toDouble();
    final nextPan = details.localFocalPoint -
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
        onDoubleTap: () => setState(() => _transform = ViewportTransform(scale: widget.initialScale.clamp(widget.minScale, widget.maxScale).toDouble())),
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
