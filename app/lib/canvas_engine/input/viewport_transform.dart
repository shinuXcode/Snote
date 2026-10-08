import 'dart:ui';

class ViewportTransform {
  final double scale;
  final Offset pan;

  const ViewportTransform({
    this.scale = 1,
    this.pan = Offset.zero,
  });

  Offset toDocument(Offset viewPoint) => Offset(
    (viewPoint.dx - pan.dx) / scale,
    (viewPoint.dy - pan.dy) / scale,
  );

  Offset toView(Offset documentPoint) => Offset(
    documentPoint.dx * scale + pan.dx,
    documentPoint.dy * scale + pan.dy,
  );

  ViewportTransform copyWith({double? scale, Offset? pan}) =>
      ViewportTransform(
        scale: scale ?? this.scale,
        pan: pan ?? this.pan,
      );
}
