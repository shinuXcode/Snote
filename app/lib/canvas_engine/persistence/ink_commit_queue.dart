import 'dart:async';

/// Coalesces document callbacks so persistence never runs from a pointer-move
/// handler. The queue only schedules the latest committed snapshot.
class InkCommitQueue<T> {
  final void Function(T value) onCommit;

  T? _pending;
  bool _scheduled = false;

  InkCommitQueue({required this.onCommit});

  void enqueue(T value) {
    _pending = value;
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_flush);
  }

  void _flush() {
    _scheduled = false;
    final value = _pending;
    _pending = null;
    if (value != null) onCommit(value);
  }

  void dispose() {
    _pending = null;
    _scheduled = false;
  }
}
