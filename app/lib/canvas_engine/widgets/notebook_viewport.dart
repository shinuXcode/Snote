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
  final bool zoomLocked;
  final int resetToken;
  final ValueChanged<ViewportTransform>? onTransformChanged;
  final InkGesturePolicy gesturePolicy;

  const NotebookViewport({
    super.key,
    required this.child,
    this.allowSingleFingerPan = false,
    this.minScale = .5,
    this.maxScale = 4,
    this.initialScale = 1,
    this.zoomLocked = false,
    this.resetToken = 0,
    this.onTransformChanged,
    this.gesturePolicy = const InkGesturePolicy(),
  });

  @override
  State<NotebookViewport> createState() => _NotebookViewportState();
}

class _NotebookViewportState extends State<NotebookViewport> {
  late ViewportTransform _transform;
  Size? _viewportSize;
  bool _centerPending = true;
  bool _layoutUpdateScheduled = false;
  bool _userMovedViewport = false;

  double _clampedInitialScale() =>
      widget.initialScale.clamp(widget.minScale, widget.maxScale).toDouble();

  /// ViewportTransform maps document points as: view = document * scale + pan.
  /// Seed pan so the viewport's center remains the zoom anchor. Without this
  /// offset, a saved zoom > 1 scales around the top-left and can move a centered
  /// notebook page completely outside the clipped viewport on initial open.
  Offset _centeredPan(double scale, Size size) => Offset(
        (1 - scale) * size.width / 2,
        (1 - scale) * size.height / 2,
      );

  void _scheduleCenter(Size size) {
    if (_layoutUpdateScheduled ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    _layoutUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutUpdateScheduled = false;
      if (!mounted) return;

      final needsCenter = _centerPending ||
          (!_userMovedViewport && _viewportSize != size);
      if (!needsCenter) return;

      final nextPan = _centeredPan(_transform.scale, size);
      setState(() {
        _transform = _transform.copyWith(pan: nextPan);
        _viewportSize = size;
        _centerPending = false;
      });
      widget.onTransformChanged?.call(_transform);
      debugPrint(
        '[Snote][Viewport] centered viewport=${size.width}x${size.height} '
        'scale=${_transform.scale} pan=${_transform.pan}',
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _transform = ViewportTransform(scale: _clampedInitialScale());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onTransformChanged?.call(_transform);
    });
  }

  @override
  void didUpdateWidget(covariant NotebookViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resetToken != widget.resetToken ||
        oldWidget.initialScale != widget.initialScale ||
        oldWidget.minScale != widget.minScale ||
        oldWidget.maxScale != widget.maxScale) {
      _transform = ViewportTransform(scale: _clampedInitialScale());
      _centerPending = true;
      _layoutUpdateScheduled = false;
      _userMovedViewport = false;
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
    _gestureDocumentFocal = _transform.toDocument(details.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_gestureAllowed || widget.zoomLocked) return;
    final nextScale = (_gestureStart.scale * details.scale)
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
      _userMovedViewport = true;
    });
    widget.onTransformChanged?.call(_transform);
  }

  void _resetView() {
    final scale = _clampedInitialScale();
    final size = _viewportSize;
    setState(() {
      _transform = ViewportTransform(
        scale: scale,
        pan: size == null ? Offset.zero : _centeredPan(scale, size),
      );
      _centerPending = size == null;
      _layoutUpdateScheduled = false;
      _userMovedViewport = false;
    });
    widget.onTransformChanged?.call(_transform);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_centerPending ||
            (!_userMovedViewport && _viewportSize != size)) {
          _scheduleCenter(size);
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: (_) {},
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
            onDoubleTap: _resetView,
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
      },
    );
  }
}
