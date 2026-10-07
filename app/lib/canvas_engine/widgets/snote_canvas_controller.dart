import 'package:flutter/foundation.dart';

class SnoteCanvasController extends ChangeNotifier {
  VoidCallback? _undoAction;
  VoidCallback? _redoAction;
  VoidCallback? _clearAction;
  VoidCallback? _deleteSelectionAction;
  VoidCallback? _duplicateSelectionAction;
  void Function(double dx, double dy)? _moveSelectionAction;
  VoidCallback? _selectAllAction;
  VoidCallback? _clearSelectionAction;

  bool _canUndo = false;
  bool _canRedo = false;
  int _selectionCount = 0;

  bool get canUndo => _canUndo;
  bool get canRedo => _canRedo;
  int get selectionCount => _selectionCount;

  void bind({
    required VoidCallback undo,
    required VoidCallback redo,
    required VoidCallback clear,
    required VoidCallback deleteSelection,
    required VoidCallback duplicateSelection,
    required void Function(double dx, double dy) moveSelection,
    required VoidCallback selectAll,
    required VoidCallback clearSelection,
    required bool canUndo,
    required bool canRedo,
    required int selectionCount,
  }) {
    _undoAction = undo;
    _redoAction = redo;
    _clearAction = clear;
    _deleteSelectionAction = deleteSelection;
    _duplicateSelectionAction = duplicateSelection;
    _moveSelectionAction = moveSelection;
    _selectAllAction = selectAll;
    _clearSelectionAction = clearSelection;
    _canUndo = canUndo;
    _canRedo = canRedo;
    _selectionCount = selectionCount;
    notifyListeners();
  }

  void undo() => _undoAction?.call();
  void redo() => _redoAction?.call();
  void clear() => _clearAction?.call();
  void deleteSelection() => _deleteSelectionAction?.call();
  void duplicateSelection() => _duplicateSelectionAction?.call();
  void moveSelection(double dx, double dy) => _moveSelectionAction?.call(dx, dy);
  void selectAll() => _selectAllAction?.call();
  void clearSelection() => _clearSelectionAction?.call();

  void unbind() {
    _undoAction = null;
    _redoAction = null;
    _clearAction = null;
    _deleteSelectionAction = null;
    _duplicateSelectionAction = null;
    _moveSelectionAction = null;
    _selectAllAction = null;
    _clearSelectionAction = null;
  }

  @override
  void dispose() {
    unbind();
    super.dispose();
  }
}
