import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart';
import 'package:snote/canvas_engine/models/pen_config.dart';
import 'package:snote/canvas_engine/widgets/snote_canvas.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records repeatable canvas, memory, and PDF baseline', (
    tester,
  ) async {
    final timings = <FrameTiming>[];
    void collectTimings(List<FrameTiming> values) => timings.addAll(values);
    binding.addTimingsCallback(collectTimings);

    const pen = PenConfig(
      type: PenType.ballpoint,
      color: Color(0xff111111),
      size: 4,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: SnoteCanvas(
              pen: pen,
              initialDocument: const <String, Object?>{
                'version': 4,
                'strokes': <Object?>[],
              },
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    final canvasRect = tester.getRect(find.byType(SnoteCanvas));
    final refreshRate = WidgetsBinding
        .instance
        .platformDispatcher
        .views
        .first
        .display
        .refreshRate;
    final safeRefreshRate =
        refreshRate.isFinite && refreshRate > 0 ? refreshRate : 60.0;
    final frameBudgetMs = 1000 / safeRefreshRate;
    final canvasRuns = <Map<String, Object?>>[];

    for (var run = 1; run <= 3; run++) {
      timings.clear();
      final rssBefore = ProcessInfo.currentRss;
      final stopwatch = Stopwatch()..start();

      for (var stroke = 0; stroke < 4; stroke++) {
        final y = canvasRect.top + 35 + ((run - 1) * 4 + stroke) * 14.0;
        final gesture = await tester.startGesture(
          Offset(canvasRect.left + 20, y),
          kind: PointerDeviceKind.stylus,
        );
        for (var point = 1; point <= 24; point++) {
          final x = canvasRect.left + 20 + point * 5.0;
          final wave = math.sin(point / 3) * 5;
          await gesture.moveTo(Offset(x, y + wave));
          await tester.pump(const Duration(milliseconds: 8));
        }
        await gesture.up();
        await tester.pump();
      }

      await tester.pump(const Duration(milliseconds: 250));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      stopwatch.stop();

      final frameSpans = timings
          .map((timing) => timing.totalSpan.inMicroseconds / 1000)
          .toList()
        ..sort();
      expect(
        frameSpans,
        isNotEmpty,
        reason: 'The emulator did not provide Flutter frame timing samples.',
      );

      double percentile(double fraction) {
        final index = ((frameSpans.length - 1) * fraction).round();
        return frameSpans[index];
      }

      final missedFrames = frameSpans.where((ms) => ms > frameBudgetMs).length;
      final result = <String, Object?>{
        'run': run,
        'refreshRateHz': safeRefreshRate,
        'frameBudgetMs': frameBudgetMs,
        'frames': frameSpans.length,
        'p50FrameMs': percentile(0.50),
        'p95FrameMs': percentile(0.95),
        'p99FrameMs': percentile(0.99),
        'framesOverBudget': missedFrames,
        'workloadElapsedMs': stopwatch.elapsedMilliseconds,
        'rssBeforeBytes': rssBefore,
        'rssAfterBytes': ProcessInfo.currentRss,
        'cumulativeCommittedStrokes': run * 4,
        'syntheticStylusEvents': 4 * 24,
      };
      canvasRuns.add(result);
      // CI preserves this line in the uploaded log artifact.
      print('SNOTE_CANVAS_BASELINE ${jsonEncode(result)}');
    }

    binding.removeTimingsCallback(collectTimings);

    final pdf = pw.Document();
    for (var pageNumber = 1; pageNumber <= 3; pageNumber++) {
      pdf.addPage(
        pw.Page(
          build: (_) => pw.Center(
            child: pw.Text('Snote emulator PDF baseline page $pageNumber'),
          ),
        ),
      );
    }
    final pdfBytes = await pdf.save();
    final pdfOpenWatch = Stopwatch()..start();
    final document = await PdfDocument.openData(pdfBytes);
    pdfOpenWatch.stop();

    final page = await document.getPage(1);
    final scale = math.min(1600 / page.width, 1600 / page.height);
    final pdfRenderWatch = Stopwatch()..start();
    final rendered = await page.render(
      width: (page.width * scale).clamp(1.0, 1600.0).toDouble(),
      height: (page.height * scale).clamp(1.0, 1600.0).toDouble(),
      format: PdfPageImageFormat.png,
      backgroundColor: '#ffffff',
    );
    pdfRenderWatch.stop();

    final pdfResult = <String, Object?>{
      'sourcePdfBytes': pdfBytes.length,
      'pageCount': document.pagesCount,
      'openMs': pdfOpenWatch.elapsedMilliseconds,
      'firstPageRenderMs': pdfRenderWatch.elapsedMilliseconds,
      'renderedPngBytes': rendered?.bytes.length ?? 0,
      'rssAfterPdfBytes': ProcessInfo.currentRss,
    };
    await page.close();
    await document.close();
    expect(rendered?.bytes.isNotEmpty, isTrue);

    final report = <String, Object?>{
      'platform': 'android-emulator-profile',
      'refreshRateHz': safeRefreshRate,
      'canvasRuns': canvasRuns,
      'pdf': pdfResult,
      'limitations': [
        'Synthetic stylus pointer events; not physical event-to-photon latency.',
        'RSS is process-level and noisy; compare repeated runs on the same emulator image.',
        'PDF timing covers PdfDocument open and first-page rasterization, not the full annotation UI.',
      ],
    };
    print('SNOTE_PERFORMANCE_BASELINE_FINAL ${jsonEncode(report)}');
  });
}
