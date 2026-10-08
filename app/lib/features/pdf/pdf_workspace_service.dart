import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../canvas_engine/models/stroke.dart';

class PdfWorkspaceService {
  const PdfWorkspaceService();

  Future<Uint8List> insertBlankPage(Uint8List bytes, int zeroBasedIndex) async {
    final document = PdfDocument(inputBytes: bytes);
    document.pages.insert(zeroBasedIndex.clamp(0, document.pages.count));
    final output = Uint8List.fromList(await document.save());
    document.dispose();
    return output;
  }

  Future<Uint8List> removePage(Uint8List bytes, int zeroBasedIndex) async {
    final document = PdfDocument(inputBytes: bytes);
    if (document.pages.count > 1 && zeroBasedIndex >= 0 && zeroBasedIndex < document.pages.count) {
      document.pages.removeAt(zeroBasedIndex);
    }
    final output = Uint8List.fromList(await document.save());
    document.dispose();
    return output;
  }

  Future<Uint8List> rotatePage(Uint8List bytes, int zeroBasedIndex) async {
    final document = PdfDocument(inputBytes: bytes);
    if (zeroBasedIndex >= 0 && zeroBasedIndex < document.pages.count) {
      final page = document.pages[zeroBasedIndex];
      page.rotation = _nextRotation(page.rotation);
    }
    final output = Uint8List.fromList(await document.save());
    document.dispose();
    return output;
  }

  Future<Uint8List> reorderPages(Uint8List bytes, List<int> oneBasedOrder) async {
    final source = PdfDocument(inputBytes: bytes);
    final output = PdfDocument();

    for (final oneBased in oneBasedOrder) {
      final index = oneBased - 1;
      if (index < 0 || index >= source.pages.count) continue;
      final template = source.pages[index].createTemplate();
      final section = output.sections!.add();
      section.pageSettings.size = template.size;
      section.pageSettings.margins.all = 0;
      section.pages.add().graphics.drawPdfTemplate(template, Offset.zero);
    }

    final result = Uint8List.fromList(await output.save());
    source.dispose();
    output.dispose();
    return result;
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
      final crop = Rect.fromLTRB(
        l,
        t,
        math.max(l + 20, size.width - r),
        math.max(t + 20, size.height - b),
      );
      final section = output.sections!.add();
      section.pageSettings.size = crop.size;
      section.pageSettings.margins.all = 0;
      section.pages.add().graphics.drawPdfTemplate(template, Offset(-crop.left, -crop.top));
    }

    final result = Uint8List.fromList(await output.save());
    source.dispose();
    output.dispose();
    return result;
  }

  Future<Uint8List> drawSnoteInk(
    Uint8List bytes,
    Map<int, List<Stroke>> strokesByPage, {
    Map<int, Size> sourceSizes = const <int, Size>{},
  }) async {
    final document = PdfDocument(inputBytes: bytes);
    for (final entry in strokesByPage.entries) {
      final pageIndex = entry.key - 1;
      if (pageIndex < 0 || pageIndex >= document.pages.count) continue;
      final page = document.pages[pageIndex];
      final size = page.getClientSize();
      for (final stroke in entry.value) {
        if (stroke.points.isEmpty) continue;
        for (var i = 0; i < stroke.points.length; i++) {
          if (i == 0 && stroke.points.length == 1) {
            final p = stroke.points.first.position;
            final radius = stroke.pen.size.clamp(.4, 40) / 2;
            final pen = PdfPen(_color(stroke.pen.color), width: math.max(.7, radius * 2));
            page.graphics.drawEllipse(
              Rect.fromCircle(center: _mapPoint(p, sourceSizes[entry.key], size), radius: radius),
              pen: pen,
            );
            continue;
          }
          if (i == 0) continue;
          final a = stroke.points[i - 1];
          final b = stroke.points[i];
          final pressure = ((a.pressure + b.pressure) / 2).clamp(.05, 1);
          final width = (stroke.pen.size * (.68 + pressure * .72)).clamp(.5, 30);
          final pen = PdfPen(_color(stroke.pen.color), width: width);
          final p1 = _mapPoint(a.position, sourceSizes[entry.key], size);
          final p2 = _mapPoint(b.position, sourceSizes[entry.key], size);
          page.graphics.drawLine(p1, p2, pen: pen);
        }
      }
    }
    final output = Uint8List.fromList(await document.save());
    document.dispose();
    return output;
  }

  Offset _mapPoint(Offset point, Size? source, Size target) {
    final width = source?.width ?? 1000;
    final height = source?.height ?? 1400;
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
