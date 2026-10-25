import 'package:flutter_test/flutter_test.dart';
import 'package:snote/canvas_engine/performance/writing_performance.dart';

void main() {
  test('uses the 60 Hz frame budget when requested', () {
    final stats = WritingPerformanceStats(enabled: true, refreshRateHz: 60);
    expect(stats.frameBudgetMs, closeTo(16.667, 0.01));

    stats.frame(const Duration(milliseconds: 17), frameBudgetMs: stats.frameBudgetMs);
    expect(stats.droppedFrames, 1);
    stats.dispose();
  });

  test('uses the 120 Hz frame budget when requested', () {
    final stats = WritingPerformanceStats(enabled: true, refreshRateHz: 120);
    expect(stats.frameBudgetMs, closeTo(8.333, 0.01));

    stats.frame(const Duration(milliseconds: 10), frameBudgetMs: stats.frameBudgetMs);
    expect(stats.droppedFrames, 1);
    stats.dispose();
  });

  test('falls back to 60 Hz for invalid refresh rates', () {
    final stats = WritingPerformanceStats(enabled: true, refreshRateHz: 0);
    expect(stats.frameBudgetMs, closeTo(16.667, 0.01));
    stats.dispose();
  });
}
