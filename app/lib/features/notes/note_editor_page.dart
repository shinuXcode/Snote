import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/widgets/page_background.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';
import '../../canvas_engine/widgets/snote_canvas_controller.dart';
import '../../core/security/note_lock_service.dart';
import '../../data/local/note_repository.dart';

class NoteEditorPage extends StatefulWidget {
  final LocalNote note;

  const NoteEditorPage({
    super.key,
    required this.note,
  });

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  final _repo = NoteRepository();
  final _canvasController = SnoteCanvasController();
  final _title = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _quill = QuillController.basic();
  final _lockService = NoteLockService();

  Timer? _saveTimer;
  Map<String, Object?> _document = {};
  PageTemplate _template = PageTemplate.lined;
  PenType _penType = PenType.ballpoint;
  Color _penColor = const Color(0xff1c2333);
  double _penSize = 3;

  bool _drawing = true;
  bool _saving = false;
  bool _locked = false;
  bool _unlocked = true;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _title.text = widget.note.title;
    _prepare();
    _quill.addListener(_scheduleSave);
  }

  Future<void> _prepare() async {
    final locked = await _lockService.isLocked(widget.note.id);

    if (!mounted) return;

    if (locked) {
      setState(() {
        _locked = true;
        _unlocked = false;
        _initializing = false;
      });

      final ok = await _lockService.authenticate();

      if (!mounted) return;

      setState(() => _unlocked = ok);

      if (ok) {
        await _load();
      }
    } else {
      await _load();
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _load() async {
    final current = await _repo.get(widget.note.id);
    if (!mounted) return;

    if (current?.contentJson != null) {
      try {
        final decoded = jsonDecode(current!.contentJson!);

        if (decoded is Map<String, dynamic>) {
          _document = decoded.cast<String, Object?>();

          final rawTemplate = decoded['template']?.toString();

          _template = PageTemplate.values.firstWhere(
            (e) => e.name == rawTemplate,
            orElse: () => PageTemplate.lined,
          );

          final rawDelta = decoded['text_delta'];

          if (rawDelta is List) {
            try {
              _quill.document = Document.fromJson(rawDelta);
            } catch (_) {}
          }
        }
      } catch (_) {
        _document = {};
      }
    }

    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  void _scheduleSave() {
    if (_locked && !_unlocked) return;

    _saveTimer?.cancel();

    _saveTimer = Timer(
      const Duration(milliseconds: 450),
      _save,
    );
  }

  Future<void> _save() async {
    if (_saving || (_locked && !_unlocked)) return;

    _saving = true;

    try {
      final document = <String, Object?>{
        ..._document,
        'version': 2,
        'template': _template.name,
        'text_delta': _quill.document.toDelta().toJson(),
      };

      await _repo.saveContent(
        widget.note.id,
        document,
      );

      final nextTitle = _title.text.trim();

      if (nextTitle.isNotEmpty &&
          nextTitle != widget.note.title) {
        await _repo.rename(
          widget.note.id,
          nextTitle,
        );
      }
    } finally {
      _saving = false;
    }
  }

  void _onCanvasChanged(
    Map<String, Object?> canvas,
  ) {
    _document = {
      ..._document,
      ...canvas,
      'version': 2,
      'template': _template.name,
      'text_delta': _quill.document.toDelta().toJson(),
    };

    _scheduleSave();
  }

  PenConfig get _pen => PenConfig(
        type: _penType,
        color: _penColor,
        size: _penSize,
        opacity: _penType == PenType.highlighter ? .34 : 1,
      );

  Future<void> _toggleLock() async {
    if (_locked) {
      final ok = await _lockService.authenticate();

      if (!mounted || !ok) return;

      await _lockService.setLocked(
        widget.note.id,
        false,
      );

      setState(() {
        _locked = false;
        _unlocked = true;
      });

      return;
    }

    await _save();

    await _lockService.setLocked(
      widget.note.id,
      true,
    );

    if (mounted) {
      setState(() => _locked = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This note is now locked.'),
        ),
      );
    }
  }

  Future<void> _pickTemplate() async {
    final selected = await showModalBottomSheet<PageTemplate>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PageTemplate.values.map(
              (template) {
                return ListTile(
                  leading: Icon(
                    template == _template
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                  ),
                  title: Text(
                    template.name.toUpperCase(),
                  ),
                  onTap: () => Navigator.pop(
                    context,
                    template,
                  ),
                );
              },
            ).toList(),
          ),
        );
      },
    );

    if (selected == null) return;

    setState(() => _template = selected);
    _scheduleSave();
  }

  Widget _lockedView() {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, size: 60),
              const SizedBox(height: 14),
              Text(
                'Note locked',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Authenticate on this device to open the note.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await _lockService.authenticate();

                  if (!mounted) return;

                  setState(() => _unlocked = ok);

                  if (ok) {
                    await _load();
                  }
                },
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_locked && !_unlocked) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.note.title),
        ),
        body: _lockedView(),
      );
    }

    final page = Stack(
      children: [
        CustomPaint(
          painter: PageBackground(
            template: _template,
          ),
          child: const SizedBox.expand(),
        ),
        if (_drawing)
          SnoteCanvas(
            pen: _pen,
            controller: _canvasController,
            initialDocument: _document,
            backgroundColor: Colors.transparent,
            onChanged: _onCanvasChanged,
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(
              24,
              20,
              24,
              28,
            ),
            child: QuillEditor(
              focusNode: _focusNode,
              scrollController: _scrollController,
              controller: _quill,
              config: const QuillEditorConfig(
                placeholder: 'Start writing…',
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _title,
          onSubmitted: (_) => _save(),
          decoration: const InputDecoration(
            hintText: 'Untitled note',
            border: InputBorder.none,
          ),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _locked ? 'Unlock note' : 'Lock note',
            onPressed: _toggleLock,
            icon: Icon(
              _locked
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
            ),
          ),
          IconButton(
            tooltip: 'Undo',
            onPressed:
                _canvasController.canUndo
                    ? _canvasController.undo
                    : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Redo',
            onPressed:
                _canvasController.canRedo
                    ? _canvasController.redo
                    : null,
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: 'Template',
            onPressed: _pickTemplate,
            icon: const Icon(Icons.grid_4x4_rounded),
          ),
          IconButton(
            tooltip: 'Clear',
            onPressed: _canvasController.clear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            _drawing ? 62 : 112,
          ),
          child: Column(
            children: [
              if (!_drawing)
                QuillSimpleToolbar(
                  controller: _quill,
                  config: const QuillSimpleToolbarConfig(),
                ),
              if (_drawing)
                SizedBox(
                  height: 62,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                    ),
                    scrollDirection: Axis.horizontal,
                    children: [
                      _toolChoice(
                        icon: Icons.edit_rounded,
                        label: 'Ballpoint',
                        selected:
                            _penType ==
                            PenType.ballpoint,
                        onTap: () => setState(
                          () => _penType =
                              PenType.ballpoint,
                        ),
                      ),
                      _toolChoice(
                        icon:
                            Icons
                                .auto_fix_high_rounded,
                        label: 'Fountain',
                        selected:
                            _penType ==
                            PenType.fountain,
                        onTap: () => setState(
                          () => _penType =
                              PenType.fountain,
                        ),
                      ),
                      _toolChoice(
                        icon: Icons.brush_rounded,
                        label: 'Pencil',
                        selected:
                            _penType ==
                            PenType.pencil,
                        onTap: () => setState(
                          () => _penType =
                              PenType.pencil,
                        ),
                      ),
                      _toolChoice(
                        icon:
                            Icons
                                .highlight_rounded,
                        label: 'Highlight',
                        selected:
                            _penType ==
                            PenType.highlighter,
                        onTap: () => setState(
                          () => _penType =
                              PenType.highlighter,
                        ),
                      ),
                      _toolChoice(
                        icon: Icons.text_fields_rounded,
                        label: 'Text',
                        selected: !_drawing,
                        onTap: () => setState(
                          () => _drawing = false,
                        ),
                      ),
                      for (final color in [
                        const Color(0xff1c2333),
                        const Color(0xff3567ff),
                        const Color(0xffcb3c52),
                        const Color(0xff198754),
                        const Color(0xff7b4fe2),
                      ])
                        IconButton(
                          tooltip: 'Ink color',
                          onPressed: () => setState(
                            () => _penColor = color,
                          ),
                          icon: CircleAvatar(
                            radius: 13,
                            backgroundColor: color,
                            child: _penColor == color
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      PopupMenuButton<double>(
                        tooltip: 'Stroke size',
                        initialValue: _penSize,
                        onSelected: (value) =>
                            setState(
                          () => _penSize = value,
                        ),
                        itemBuilder: (context) =>
                            const [
                          PopupMenuItem(
                            value: 1.5,
                            child: Text('Fine'),
                          ),
                          PopupMenuItem(
                            value: 3,
                            child: Text('Regular'),
                          ),
                          PopupMenuItem(
                            value: 5,
                            child: Text('Bold'),
                          ),
                          PopupMenuItem(
                            value: 8,
                            child: Text('Marker'),
                          ),
                        ],
                        child: Padding(
                          padding:
                              const EdgeInsets
                                  .symmetric(
                            horizontal: 8,
                          ),
                          child: Center(
                            child: Text(
                              '${_penSize.toStringAsFixed(1)} px',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!_drawing)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _drawing = true,
                    ),
                    icon: const Icon(
                      Icons.draw_rounded,
                    ),
                    label: const Text(
                      'Back to ink',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      body: InteractiveViewer(
        minScale: .45,
        maxScale: 4,
        boundaryMargin: const EdgeInsets.all(500),
        child: Center(
          child: AspectRatio(
            aspectRatio: 210 / 297,
            child: Material(
              elevation: 5,
              child: page,
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolChoice({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        avatar: Icon(icon, size: 17),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    if (!_locked || _unlocked) {
      unawaited(_save());
    }
    _title.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _quill.dispose();
    _canvasController.dispose();
    super.dispose();
  }
}
