import 'package:flutter/material.dart';

import '../../../core/settings/app_settings.dart';
import '../../../data/local/note_repository.dart';
import 'editor_v2_page.dart';

/// Two independently editable notes in a resizable side-by-side workspace.
class MultiSplitNoteWorkspace extends StatefulWidget {
  final LocalNote firstNote;
  final LocalNote secondNote;

  const MultiSplitNoteWorkspace({
    super.key,
    required this.firstNote,
    required this.secondNote,
  });

  @override
  State<MultiSplitNoteWorkspace> createState() => _MultiSplitNoteWorkspaceState();
}

class _MultiSplitNoteWorkspaceState extends State<MultiSplitNoteWorkspace> {
  late double _leftPercent;

  @override
  void initState() {
    super.initState();
    final savedRatio = SnoteSettings.instance.getDouble('multiSplitLeftPercent');
    _leftPercent = savedRatio >= 30 && savedRatio <= 70 ? savedRatio : 50;
  }

  Future<void> _saveRatio(double value) async {
    setState(() => _leftPercent = value.clamp(30.0, 70.0).toDouble());
    await SnoteSettings.instance.setDouble('multiSplitLeftPercent', _leftPercent);
  }

  Widget _editorPane(LocalNote note, double width, double height) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(size: Size(width, height)),
      child: EditorV2Page(note: note),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Split notes'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Text(
                '${_leftPercent.round()} / ${(100 - _leftPercent).round()}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.view_column_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _leftPercent,
                      min: 30,
                      max: 70,
                      divisions: 8,
                      label: '${_leftPercent.round()} / ${(100 - _leftPercent).round()}',
                      onChanged: (value) => setState(() => _leftPercent = value),
                      onChangeEnd: _saveRatio,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.view_column_rounded, size: 18),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final height = constraints.maxHeight;
                final leftWidth = width * _leftPercent / 100;
                final rightWidth = width - leftWidth;
                return Row(
                  children: [
                    SizedBox(
                      width: leftWidth,
                      child: _editorPane(widget.firstNote, leftWidth, height),
                    ),
                    VerticalDivider(
                      width: 2,
                      thickness: 2,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    SizedBox(
                      width: rightWidth - 2,
                      child: _editorPane(widget.secondNote, rightWidth - 2, height),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
