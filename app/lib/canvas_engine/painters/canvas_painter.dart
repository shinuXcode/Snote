  void _drawLivePath(Canvas canvas) {
    if (activePath == null || activePen == null || activeTool == null) return;
    final opacity = activePen!.type == PenType.highlighter
        ? activePen!.opacity.clamp(.08, .55)
        : activePen!.opacity.clamp(.05, 1);
    final paint = Paint()
      ..color = activePen!.color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (activePen!.type == PenType.highlighter ? activePen!.size * 2.05 : activePen!.size).clamp(.5, 60).toDouble()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true
      ..blendMode = activePen!.type == PenType.highlighter ? BlendMode.multiply : BlendMode.srcOver;
    canvas.drawPath(activePath!, paint);
    if (activePoints.isNotEmpty) {
      final last = activePoints.last.position;
      canvas.drawCircle(last, math.max(.6, paint.strokeWidth / 2), Paint()..color = paint.color);
    }
  }

  void _drawActive(Canvas canvas) {
    final stroke = Stroke(
      id: 'active',
      points: activePoints,
      pen: activePen!,
      shape: activeTool!.isShape ? activeTool!.name : null,
      fill: activeFill,
      customSides: activeCustomSides,
      stickerText: activeStickerText,
    );
    _drawStroke(canvas, stroke, false);
  }

  void _drawStroke(Canvas canvas, Stroke stroke, bool selected) {
    if (stroke.stickerText != null) {
      _drawSticker(canvas, stroke.points.first.position, stroke.stickerText!);
      return;
    }

    final points = stroke.points;
    if (points.isEmpty) return;
    final color = stroke.pen.color.withValues(alpha: stroke.pen.opacity.clamp(0, 1));

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.pen.size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (selected) {
      final bounds = _bounds(points);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds.inflate(9), const Radius.circular(9)),
        Paint()..color = const Color(0xff4f6df6).withValues(alpha: .16),
      );
    }

    if (stroke.shape != null) {
      _drawShape(canvas, stroke, paint);
      return;
    }

    if (points.length == 1) {
      canvas.drawCircle(points.first.position, math.max(1, stroke.pen.size / 2), Paint()..color = color);
      return;
    }

    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      var width = stroke.pen.size.clamp(.5, 60).toDouble();
      if (stroke.pen.type == PenType.fountain) {
        final dt = (b.timestamp - a.timestamp).clamp(.5, 250.0);
        final velocity = (b.position - a.position).distance / dt;
        width = fountainWidth(
          baseWidth: width,
          velocity: velocity * (0.55 + stroke.pen.velocitySensitivity * 1.45),
          pressure: .45 + b.pressure * (.55 + stroke.pen.pressureSensitivity * .45),
        );
      } else if (stroke.pen.type == PenType.pencil) {
        width *= .78 + b.pressure.clamp(0, 1) * (.22 + stroke.pen.pressureSensitivity * .32);
      } else {
        width *= .82 + b.pressure.clamp(0, 1) * (.12 + stroke.pen.pressureSensitivity * .22);
      }

      paint.strokeWidth = stroke.pen.type == PenType.highlighter ? width * 2.05 : width;
      paint.blendMode = stroke.pen.type == PenType.highlighter ? BlendMode.multiply : BlendMode.srcOver;

      canvas.drawLine(a.position, b.position, paint);
    }
  }

  void _drawShape(Canvas canvas, Stroke stroke, Paint paint) {
    if (stroke.points.length < 2) return;
    final a = stroke.points.first.position;
    final b = stroke.points.last.position;
    final rect = Rect.fromPoints(a, b);
    final shapePaint = Paint()
      ..color = paint.color
      ..style = paint.style
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = paint.strokeCap
      ..strokeJoin = paint.strokeJoin