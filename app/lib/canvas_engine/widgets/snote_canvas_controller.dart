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
  void Function(Color color)? _changeColorAction;
  void Function(double size)? _changeSizeAction;
  VoidCallback? _toggleFillAction;
  VoidCallback? _bringToFrontAction;
  VoidCallback? _sendToBackAction;

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
    void Function(Color color)? changeColor,
    void Function(double size)? changeSize,
    VoidCallback? toggleFill,
    VoidCallback? bringToFront,
    VoidCallback? sendToBack,
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
    _changeColorAction = changeColor;
    _changeSizeAction = changeSize;
    _toggleFillAction = toggleFill;
    _bringToFrontAction = bringToFront;
    _sendToBackAction = sendToBack;
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
  void changeColor(Color color) => _changeColorAction?.call(color);
  void changeSize(double size) => _changeSizeAction?.call(size);
  void toggleFill() => _toggleFillAction?.call();
  void bringToFront() => _bringToFrontAction?.call();
  void sendToBack() => _sendToBackAction?.call();

  void unbind() {
    _undoAction = null;
    _redoAction = null;
    _clearAction = null;
    _deleteSelectionAction = null;
    _duplicateSelectionAction = null;
    _moveSelectionAction = null;
    _selectAllAction = null;
    _clearSelectionAction = null;
    _changeColorAction = null;
    _changeSizeAction = null;
    _toggleFillAction = null;
    _bringToFrontAction = null;
    _sendToBackAction = null;
  }

  @override
  void dispose() {
    unbind();
    super.dispose();
  }
}