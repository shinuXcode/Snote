
    if (_temporaryEraser) {
      _activeTool = CanvasTool.eraser;
      _activePen = widget.pen;
      _eraserPoint = point;
      _eraserRadius = _eraseRadius(event.pressure);
      if (!_eraseSnapshotTaken) {
        _snapshot();
        _eraseSnapshotTaken = true;
      }
      _eraseAt(point, pressure: event.pressure, snapshotAlreadyTaken: true);
      _repaint.repaint();
      return;
    }

    if (widget.tool == CanvasTool.lasso) {
      _lassoPath..clear()..add(point);
      _repaint.repaint();
      return;
    }

    if (widget.tool == CanvasTool.eraser) {
      if (!_eraseSnapshotTaken) {
        _snapshot();
        _eraseSnapshotTaken = true;
      }
      _eraseAt(point, pressure: event.pressure, snapshotAlreadyTaken: true);
      return;
    }

    _activeTool = widget.tool;
    _activePen = widget.pen;
    _activePath = Path()..moveTo(point.dx, point.dy);
    _liveLastPoint = point;
    _activeSticker = widget.tool == CanvasTool.sticker ? widget.stickerText : null;
    _activePoints
      ..clear()
      ..add(_sample(point, event.pressure, event.timeStamp));
    if (widget.tool == CanvasTool.sticker) {
      _commitActive();
    } else {
      _repaint.repaint();
    }
  }

  StrokePoint _sample(Offset position, double pressure, Duration timeStamp) {
    return StrokePoint(
      position: position,
      pressure: pressure.isNaN ? 1 : pressure.clamp(0, 1),
      timestamp: timeStamp.inMicroseconds / 1000,
    );
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer || _ignorePointer) return;

    if (widget.tool == CanvasTool.eraser || _temporaryEraser) {
      _eraserPoint = event.localPosition;
      _eraserRadius = _eraseRadius(event.pressure);
      _eraseAt(event.localPosition, pressure: event.pressure, snapshotAlreadyTaken: _eraseSnapshotTaken);
      _repaint.repaint();
      return;
    }
    if (widget.tool == CanvasTool.lasso) {
      _lassoPath.add(event.localPosition);
      _repaint.repaint();
      return;
    }
    if (_activePen == null || _activeTool == null) return;

    final position = event.localPosition;
    if (_activePoints.isNotEmpty &&
        (position - _activePoints.last.position).distance < .7) {
      return;
    }

    _activePoints.add(_sample(position, event.pressure, event.timeStamp));
    final previous = _liveLastPoint ?? _activePoints[_activePoints.length - 2].position;
    final midpoint = Offset((previous.dx + position.dx) / 2, (previous.dy + position.dy) / 2);
    _activePath ??= Path()..moveTo(previous.dx, previous.dy);
    _activePath!.quadraticBezierTo(previous.dx, previous.dy, midpoint.dx, midpoint.dy);
    _liveLastPoint = position;
    _repaint.repaint();
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    if (_ignorePointer) {
      _ignorePointer = false;
      _activePointer = -1;
      return;
    }

    if (_temporaryEraser) {
      _eraseSnapshotTaken = false;
      _temporaryEraser = false;
      _eraserPoint = null;
      _eraserRadius = 0;
      _cancelActive();
    } else if (widget.tool == CanvasTool.lasso) {
      _finishLasso();
    } else if (widget.tool != CanvasTool.eraser && widget.tool != CanvasTool.sticker) {
      if (_activePoints.isNotEmpty) _commitActive();
    }

    if (widget.tool == CanvasTool.eraser) {
      _eraseSnapshotTaken = false;
      _eraserPoint = null;
      _eraserRadius = 0;
    }

    if (event.kind == PointerDeviceKind.stylus) {
      _lastStylusTap = DateTime.now();
      _lastStylusPosition = event.localPosition;
    }
    _activePointer = -1;
  }

  void _pointerCancel(PointerCancelEvent event) {