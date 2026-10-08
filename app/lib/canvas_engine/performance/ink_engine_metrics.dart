import 'dart:ui';

/// Lightweight engine-side metrics. Enabled only by the caller in developer
/// builds so the production hot path remains free of overlay work.
class InkEngineMetrics {
  int inputSamples = 0;
  int committedSamples = 0;
  int predictedSamples = 0;
  int droppedRedundantSamples = 0;
  int predictionCorrections = 0;
  double maxPredictionError = 0;
  double maxInputGapMs = 0;

  void sample(double gapMs) {
    inputSamples++;
    if (gapMs > maxInputGapMs) maxInputGapMs = gapMs;
  }

  void redundant() => droppedRedundantSamples++;
  void predicted() => predictedSamples++;

  void predictionError(double error) {
    predictionCorrections++;
    if (error > maxPredictionError) maxPredictionError = error;
  }

  void commit(int count) => committedSamples += count;

  Offset? lastPosition;
}
