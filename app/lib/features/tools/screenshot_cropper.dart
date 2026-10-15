import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Lets the user crop a captured image before it is inserted into a note.
class SnoteScreenshotCropper {
  const SnoteScreenshotCropper._();

  static Future<Uint8List?> crop(BuildContext context, Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      if (!context.mounted) return null;
      final normalized = await showDialog<Rect>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ScreenshotCropDialog(image: image),
      );
      if (normalized == null) return null;

      final left = (normalized.left * image.width)
          .clamp(0.0, image.width - 1.0)
          .toDouble();
      final top = (normalized.top * image.height)
          .clamp(0.0, image.height - 1.0)
          .toDouble();
      final right = (normalized.right * image.width)
          .clamp(left + 1.0, image.width.toDouble())
          .toDouble();
      final bottom = (normalized.bottom * image.height)
          .clamp(top + 1.0, image.height.toDouble())
          .toDouble();
      final source = Rect.fromLTRB(left, top, right, bottom);
      final width = math.max(1, source.width.ceil());
      final height = math.max(1, source.height.ceil());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        image,
        source,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(width, height);
      picture.dispose();
      try {
        final data = await croppedImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return data?.buffer.asUint8List();
      } finally {
        croppedImage.dispose();
      }
    } finally {
      image.dispose();
      codec.dispose();
    }
  }
}

class _ScreenshotCropDialog extends StatefulWidget {
  final ui.Image image;

  const _ScreenshotCropDialog({required this.image});

  @override
  State<_ScreenshotCropDialog> createState() => _ScreenshotCropDialogState();
}

class _ScreenshotCropDialogState extends State<_ScreenshotCropDialog> {
  Offset? _start;
  Rect? _selection;

  Offset _clamp(Offset point, Size size) => Offset(
        point.dx.clamp(0.0, size.width).toDouble(),
        point.dy.clamp(0.0, size.height).toDouble(),
      );

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final aspect = widget.image.width / widget.image.height;
    final maxWidth = math.min(640.0, media.width - 48);
    final maxHeight = (media.height - 230).clamp(160.0, 560.0).toDouble();
    final areaWidth = math.min(maxWidth, maxHeight * aspect);
    final areaHeight = areaWidth / aspect;
    final selection = _selection;
    final canCrop = selection != null &&
        selection.width >= 8 &&
        selection.height >= 8;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Select screenshot area',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel crop',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Drag over the area to insert. The original capture is not changed.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: areaWidth,
              height: areaHeight,
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RawImage(image: widget.image, fit: BoxFit.fill),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (details) {
                        final point = _clamp(details.localPosition, Size(areaWidth, areaHeight));
                        setState(() {
                          _start = point;
                          _selection = Rect.fromPoints(point, point);
                        });
                      },
                      onPanUpdate: (details) {
                        final start = _start;
                        if (start == null) return;
                        final point = _clamp(details.localPosition, Size(areaWidth, areaHeight));
                        setState(() => _selection = Rect.fromPoints(start, point));
                      },
                      onPanEnd: (_) => setState(() => _start = null),
                      child: CustomPaint(
                        painter: _ScreenshotCropOverlay(selection: selection),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: canCrop
                      ? () {
                          final rect = selection!;
                          Navigator.pop(
                            context,
                            Rect.fromLTRB(
                              rect.left / areaWidth,
                              rect.top / areaHeight,
                              rect.right / areaWidth,
                              rect.bottom / areaHeight,
                            ),
                          );
                        }
                      : null,
                  icon: const Icon(Icons.crop_rounded),
                  label: const Text('Crop & insert'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenshotCropOverlay extends CustomPainter {
  final Rect? selection;

  const _ScreenshotCropOverlay({required this.selection});

  @override
  void paint(Canvas canvas, Size size) {
    final selected = selection;
    if (selected == null || selected.width < 1 || selected.height < 1) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: .18),
      );
      return;
    }

    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(selected);
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: .55),
    );
    canvas.drawRect(
      selected,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final cornerPaint = Paint()
      ..color = ThemeColor.cropAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    const cornerLength = 15.0;
    for (final point in <Offset>[
      selected.topLeft,
      selected.topRight,
      selected.bottomLeft,
      selected.bottomRight,
    ]) {
      final dx = point == selected.topRight || point == selected.bottomRight
          ? -cornerLength
          : cornerLength;
      final dy = point == selected.bottomLeft || point == selected.bottomRight
          ? -cornerLength
          : cornerLength;
      canvas.drawLine(point, point.translate(dx, 0), cornerPaint);
      canvas.drawLine(point, point.translate(0, dy), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenshotCropOverlay oldDelegate) =>
      oldDelegate.selection != selection;
}

class ThemeColor {
  static const cropAccent = Color(0xff6d5ce7);
}
