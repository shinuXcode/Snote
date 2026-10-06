import 'package:flutter/foundation.dart';

class SnoteCanvasController extends ChangeNotifier {
  VoidCallback? _undoAction;
  VoidCallback? _redoAction;
  VoidCallback? _clearAction;

  bool _canUndo = false;
  bool _canRedo = false;

  bool get canUndo => _canUndo;
  bool get canRedo => _canRedo;

  void bind({
    required VoidCallback undo,
    required VoidCallback redo,
    required VoidCallback clear,
    required bool canUndo,
    required bool canRedo,
  }) {
    _undoAction = undo;
    _redoAction = redo;
    _clearAction = clear;
    _canUndo = canUndo;
    _canRedo = canRedo;
    notifyListeners();
  }

  void undo() => _undoAction?.call();
  void redo() => _redoAction?.call();
  void clear() => _clearAction?.call();

  void unbind() {
    _undoAction = null;
    _redoAction = null;
    _clearAction = null;
  }

  @override
  void dispose() {
    unbind();
    super.dispose();
  }
}
