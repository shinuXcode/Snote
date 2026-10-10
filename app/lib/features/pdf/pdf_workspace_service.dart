import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../canvas_engine/models/stroke.dart';

class PdfWorkspaceService {
  const PdfWorkspaceService();

  Future<Uint8List> insertBlankPage(
    Uint8List bytes,
    int zeroBasedIndex,
  ) async {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final index = zeroBasedIndex.clamp(0, document.pages.count).toInt();
      document.pages.insert(index);
      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  Future<Uint8List> removePage(Uint8List bytes, int zeroBasedIndex) async {
    final document = PdfDocument(inputBytes: bytes);
    try {
      if (document.pages.count > 1 &&
          zeroBasedIndex >= 0 &&
          zeroBasedIndex < document.pages.count) {
        document.pages.removeAt(zeroBasedIndex);
      }
      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  Future<Uint8List> rotatePage(Uint8List bytes, int zeroBasedIndex) async {
    final document = PdfDocument(inputBytes: bytes);
    try {
      if (zeroBasedIndex >= 0 && zeroBasedIndex < document.pages.count) {
        final page = document.pages[zeroBasedIndex];
        page.rotation = _nextRotation(page.rotation);
      }
      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  Future<Uint8List> reorderPages(
    Uint8List bytes,
    List<int> oneBasedOrder,
  ) async {
    final source = PdfDocument(inputBytes: bytes);
    final output = PdfDocument();
    try {
      final pageCount = source.pages.count;
      final expected = List<int>.generate(pageCount, (index) => index + 1);
      if (oneBasedOrder.length != pageCount ||
          oneBasedOrder.toSet().length != pageCount ||
          !oneBasedOrder.toSet().containsAll(expected) ||
          !expected.toSet().containsAll(oneBasedOrder)) {
        throw ArgumentError.value(
          oneBasedOrder,
          'oneBasedOrder',
          'Order must contain each source page exactly once.',
        );
      }

      for (final oneBased in oneBasedOrder) {
        final template = source.pages[oneBased - 1].createTemplate();
        final section = output.sections!.add();
        section.pageSettings.size = template.size;
        section.pageSettings.margins.all = 0;
        section.pages.add().graphics.drawPdfTemplate(template, Offset.zero);
      }

      return Uint8List.fromList(await output.save());
    } finally {
      source.dispose();
      output.dispose();
    }
  }

  Future<Uint8List> cropPage(
    Uint8List bytes,
    int zeroBasedIndex, {
    double left = .04,
    double top = .04,
    double right = .04,
    double bottom = .04,
  }) async {
    final source = PdfDocument(inputBytes: bytes);
    final output = PdfDocument();
    try {
      if (zeroBasedIndex < 0 || zeroBasedIndex >= source.pages.count) {
        // Invalid page indices are a no-op, not a destructive document rewrite.
        return Uint8List.fromList(bytes);
      }

      for (var i = 0; i < source.pages.count; i++) {
        final template = source.pages[i].createTemplate();
        final size = template.size;
        if (i != zeroBasedIndex) {
          final section = output.sections!.add();
          section.pageSettings.size = size;
          section.pageSettings.margins.all = 0;
          section.pages.add().graphics.drawPdfTemplate(template, Offset.zero);
          continue;
        }

        final l = (size.width * left.clamp(0, .45)).toDouble();
        final t = (size.height * top.clamp(0, .45)).toDouble();
        final r = (size.width * right.clamp(0, .45)).toDouble();
        final b = (size.height * bottom.clamp(0, .45)).toDouble();
        final cropLeft = l.clamp(0.0, math.max(0.0, size.width - 20)).toDouble();
        final cropTop = t.clamp(0.0, math.max(0.0, size.height - 20)).toDouble();
        final cropRight = math.max(cropLeft + 20, size.width - r)
            .clamp(cropLeft + 20, math.max(cropLeft + 20, size.width))
            .toDouble();
        final cropBottom = math.max(cropTop + 20, size.height - b)
            .clamp(cropTop + 20, math.max(cropTop + 20, size.height))
            .toDouble();
        final crop = Rect.fromLTRB(
          cropLeft,
          cropTop,
          cropRight,
          cropBottom,
        );
        final section = output.sections!.add();
        section.pageSettings.size = crop.size;
        section.pageSettings.margins.all = 0;
        section.pages.add().graphics.drawPdfTemplate(
              template,
              Offset(-crop.left, -crop.top),
            );
      }

      return Uint8List.fromList(await output.save());
    } finally {
      source.dispose();
      output.dispose();
    }
  }

  Future<Uint8List> drawSnoteInk(
    Uint8List bytes,
    Map<int, List<Stroke>> strokesByPage, {
    Map<int, Size> sourceSizes = const <int, Size>{},
  }) async {
    final document = PdfDocument(inputBytes: bytes);
    try {
      for (final entry in strokesByPage.entries) {
        final pageIndex = entry.key - 1;
        if (pageIndex < 0 || pageIndex >= document.pages.count) continue;
        final page = document.pages[pageIndex];
        final size = page.getClientSize();
        for (final stroke in entry.value) {
          if (stroke.points.isEmpty) continue;
          for (var i = 0; i < stroke.points.length; i++) {
            if (i == 0 && stroke.points.length == 1) {
              final point = stroke.points.first.position;
              final radius = stroke.pen.size.clamp(.4, 40).toDouble() / 2;
              final pen = PdfPen(
                _color(stroke.pen.color),
                width: math.max(.7, radius * 2).toDouble(),
              );
              page.graphics.drawEllipse(
                Rect.fromCircle(
                  center: _mapPoint(point, sourceSizes[entry.key], size),
                  radius: radius,
                ),
                pen: pen,
              );
              continue;
            }
            if (i == 0) continue;
            final a = stroke.points[i - 1];
            final b = stroke.points[i];
            final pressure =
                ((a.pressure + b.pressure) / 2).clamp(.05, 1).toDouble();
            final width = (stroke.pen.size * (.68 + pressure * .72))
                .clamp(.5, 30)
                .toDouble();
            final pen = PdfPen(_color(stroke.pen.color), width: width);
            final p1 = _mapPoint(a.position, sourceSizes[entry.key], size);
            final p2 = _mapPoint(b.position, sourceSizes[entry.key], size);
            page.graphics.drawLine(p1, p2, pen: pen);
          }
        }
      }
      return Uint8List.fromList(await document.save());
    } finally {
      document.dispose();
    }
  }

  Offset _mapPoint(Offset point, Size? source, Size target) {
    final width = source?.width ?? 1000;
    final height = source?.height ?? 1400;
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw ArgumentError('Ink source dimensions must be finite and positive.');
    }
    return Offset(
      point.dx * target.width / width,
      point.dy * target.height / height,
    );
  }

  PdfColor _color(Color color) {
    final argb = color.toARGB32();
    return PdfColor(
      (argb >> 16) & 0xff,
      (argb >> 8) & 0xff,
      argb & 0xff,
    );
  }

  PdfPageRotateAngle _nextRotation(PdfPageRotateAngle current) {
    switch (current) {
      case PdfPageRotateAngle.rotateAngle0:
        return PdfPageRotateAngle.rotateAngle90;
      case PdfPageRotateAngle.rotateAngle90:
        return PdfPageRotateAngle.rotateAngle180;
      case PdfPageRotateAngle.rotateAngle180:
        return PdfPageRotateAngle.rotateAngle270;
      case PdfPageRotateAngle.rotateAngle270:
        return PdfPageRotateAngle.rotateAngle0;
    }
  }
}
