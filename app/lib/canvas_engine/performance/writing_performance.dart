import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WritingPerformanceStats extends ChangeNotifier {
  final bool enabled;
  final List<Duration> _frameDurations = <Duration>[];
  DateTime _windowStart = DateTime.now();
  int _pointerEvents = 0;
  int _renderedPoints = 0;
  int _frames = 0;
  int _droppedFrames = 0;
  double _predictionHorizon = 0;
  double _estimatedLatencyMs = 0;
  int _strokeCount = 0;
  int _visibleStrokes = 0;
  int _lastWindowPointer = 0;
  int _lastWindowPoints = 0;
  int _lastWindowFrames = 0;

  WritingPerformanceStats({this.enabled = kDebugMode});

  double get pointerEventsPerSecond => _lastWindowPointer.toDouble();
  double get renderedPointsPerSecond => _lastWindowPoints.toDouble();
  double get fps => _lastWindowFrames.toDouble();

  double get refreshRate {
    final views = PlatformDispatcher.instance.views;
    if (views.isEmpty) return 60;
    final rate = views.first.display.refreshRate;
    return rate.isFinite && rate > 1 ? rate : 60;
  }

  double get frameBudgetMs => 1000 / refreshRate;

  double get frameTimeMs {
    if (_frameDurations.isEmpty) return 0;
    final sum = _frameDurations.fold<int>(
      0,
      (value, duration) => value + duration.inMicroseconds,
    );
    return sum / _frameDurations.length / 1000;
  }

  int get droppedFrames => _droppedFrames;
  double get predictionHorizonMs => _predictionHorizon;
  double get estimatedLatencyMs => _estimatedLatencyMs;
  int get strokeCount => _strokeCount;
  int get visibleStrokes => _visibleStrokes;
  int get imageCacheBytes =>
      PaintingBinding.instance.imageCache.currentSizeBytes;

  void pointerEvent() {
    if (!enabled) return;
    _pointerEvents++;
    _rollWindow();
  }

  void rendered(int points) {
    if (!enabled) return;
    _renderedPoints += points;
    _rollWindow();
  }

  void setPredictionHorizon(double ms) {
    if (!enabled) return;
    _predictionHorizon = ms;
    notifyListeners();
  }

  void setDocumentStats({
    required int strokes,
    required int visible,
  }) {
    if (!enabled) return;
    _strokeCount = strokes;
    _visibleStrokes = visible;
    notifyListeners();
  }

  void setLatency(DateTime inputAt) {
    if (!enabled) return;
    _estimatedLatencyMs =
        DateTime.now().difference(inputAt).inMicroseconds / 1000;
  }

  void frame(Duration duration, {required double frameBudgetMs}) {
    if (!enabled) return;
    _frames++;
    _frameDurations.add(duration);
    if (_frameDurations.length > 120) {
      _frameDurations.removeAt(0);
    }
    if (duration.inMicroseconds > frameBudgetMs * 1000) {
      _droppedFrames++;
    }
    _rollWindow();
  }

  void attachScheduler() {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  void detachScheduler() {
    if (!enabled) return;
    SchedulerBinding.instance.removeTimingsCallback(_timings);
  }

  void _timings(List<FrameTiming> timings) {
    for (final timing in timings) {
      frame(
        timing.totalSpan,
        frameBudgetMs: 16.667,
      );
    }
  }

  void _rollWindow() {
    final now = DateTime.now();
    if (now.difference(_windowStart) <
        const Duration(seconds: 1)) {
      notifyListeners();
      return;
    }
    _lastWindowPointer = _pointerEvents;
    _lastWindowPoints = _renderedPoints;
    _lastWindowFrames = _frames;
    _pointerEvents = 0;
    _renderedPoints = 0;
    _frames = 0;
    _windowStart = now;
    notifyListeners();
  }
}

class WritingPerformanceOverlay extends StatelessWidget {
  final WritingPerformanceStats stats;

  const WritingPerformanceOverlay({
    super.key,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      top: 8,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: stats,
          builder: (_, __) => DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: DefaultTextStyle(
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  height: 1.25,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                child: Text(
                  'Snote Writing Perf\n'
                  'FPS ${stats.fps.toStringAsFixed(0)} / ${stats.refreshRate.toStringAsFixed(0)}  '
                  'Frame ${stats.frameTimeMs.toStringAsFixed(1)} ms\n'
                  'Ptr/s ${stats.pointerEventsPerSecond.toStringAsFixed(0)}  '
                  'Pts/s ${stats.renderedPointsPerSecond.toStringAsFixed(0)}\n'
                  'Dropped ${stats.droppedFrames}  '
                  'Latency ${stats.estimatedLatencyMs.toStringAsFixed(1)} ms\n'
                  'Predict ${stats.predictionHorizonMs.toStringAsFixed(1)} ms  '
                  'Strokes ${stats.strokeCount} / ${stats.visibleStrokes}\n'
                  'Image cache ${(stats.imageCacheBytes / 1024).round()} KB',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
