import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'screen_capture.dart';

/// Lets a user sample a color from the visible display.
class SnoteScreenColorPicker {
  const SnoteScreenColorPicker._();

  static Future<Color?> pick(BuildContext context) async {
    ui.Image? image;
    ui.Codec? codec;
    try {
      final bytes = await SnoteScreenCapture.captureDisplay();
      if (bytes == null || bytes.isEmpty) {
        _showError(context, 'Screen capture returned no image. Check the capture permission.');
        return null;
      }
      codec = await ui.instantiateImageCodec(bytes);
      image = (await codec.getNextFrame()).image;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) {
        _showError(context, 'This screen image could not be sampled.');
        return null;
      }
      if (!context.mounted) return null;

      final media = MediaQuery.sizeOf(context);
      final maxWidth = math.max(180.0, math.min(900.0, media.width - 48));
      final maxHeight = math.max(120.0, media.height - 210);
      var previewWidth = math.min(maxWidth, maxHeight * image.width / image.height);
      var previewHeight = previewWidth * image.height / image.width;
      if (previewHeight > maxHeight) {
        previewHeight = maxHeight;
        previewWidth = previewHeight * image.width / image.height;
      }

      final point = await showDialog<Offset>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Eyedropper'),
          content: SizedBox(
            width: previewWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Tap the exact pixel whose color you want to sample.'),
                const SizedBox(height: 10),
                SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      final position = details.localPosition;
                      if (position.dx < 0 || position.dy < 0 ||
                          position.dx >= previewWidth || position.dy >= previewHeight) {
                        return;
                      }
                      final x = (position.dx / previewWidth * image!.width)
                          .floor().clamp(0, image.width - 1);
                      final y = (position.dy / previewHeight * image.height)
                          .floor().clamp(0, image.height - 1);
                      Navigator.of(dialogContext, rootNavigator: true).pop(
                        Offset(x.toDouble(), y.toDouble()),
                      );
                    },
                    child: RawImage(image: image, fit: BoxFit.fill),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (point == null) return null;
      final x = point.dx.toInt().clamp(0, image.width - 1);
      final y = point.dy.toInt().clamp(0, image.height - 1);
      final offset = (y * image.width + x) * 4;
      return Color.fromARGB(
        rgba.getUint8(offset + 3),
        rgba.getUint8(offset),
        rgba.getUint8(offset + 1),
        rgba.getUint8(offset + 2),
      );
    } catch (error) {
      if (context.mounted) {
        _showError(context, 'Eyedropper unavailable: $error');
      }
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }
}
