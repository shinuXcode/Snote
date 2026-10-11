
import 'dart:convert';

import 'package:flutter/material.dart';
import '../../data/local/note_repository.dart';

class MindMapPage extends StatefulWidget {
  final String? folderId;
  final LocalNote? note;
  const MindMapPage({super.key, this.folderId, this.note});
  @override
  State<MindMapPage> createState() => _MindMapPageState();
}

class _MindMapPageState extends State<MindMapPage> {
  final _notes = NoteRepository();
  final List<Map<String, dynamic>> _nodes = [
    {'id': 'root', 'parentId': null, 'text': 'Main idea', 'x': 80.0, 'y': 280.0},
  ];
  final List<Map<String, String>> _edges = [];
  int _counter = 1;
  String _parentId = 'root';
  Color _background = const Color(0xfff4f6fb);

  @override
  void initState() {
    super.initState();
    try {
      final decoded = jsonDecode(widget.note?.contentJson ?? '{}');
      if (decoded is Map && decoded['mindMap'] is Map) {
        final map = decoded['mindMap'] as Map;
        if (map['nodes'] is List) {
          final loaded = (map['nodes'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
              .toList();
          if (loaded.isNotEmpty) {
            _nodes
              ..clear()
              ..addAll(loaded);
          }
        }
        if (map['edges'] is List) {
          _edges
            ..clear()
            ..addAll((map['edges'] as List).whereType<Map>().map((item) => <String, String>{
              'from': item['from']?.toString() ?? '',
              'to': item['to']?.toString() ?? '',
            }));
        }
        final backgroundValue = map['background'];
        if (backgroundValue is num) _background = Color(backgroundValue.toInt());
        var maxId = 0;
        for (final node in _nodes) {
          final match = RegExp(r'^node(\\d+)
    final c = TextEditingController(text: 'New idea');
    final textValue = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Add child branch'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Idea')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Add branch')),
        ],
      ),
    );
    c.dispose();
    if (textValue == null || textValue.trim().isEmpty) return;
    setState(() {
      final parent = _nodes.firstWhere((n) => n['id'] == _parentId, orElse: () => _nodes.first);
      final siblings = _edges.where((e) => e['from'] == _parentId).length;
      final id = 'node' + (_counter++).toString();
      final px = (parent['x'] as num).toDouble();
      final py = (parent['y'] as num).toDouble();
      _nodes.add({
        'id': id, 'parentId': _parentId, 'text': textValue.trim(),
        'x': px + 260.0, 'y': py + (siblings - .5) * 115.0,
      });
      _edges.add({'from': _parentId, 'to': id});
    });
  }

  Future<void> _chooseParent() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Choose parent idea'),
        children: _nodes.map((node) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, node['id'].toString()),
          child: Text(node['text'].toString()),
        )).toList(),
      ),
    );
    if (selected != null) setState(() => _parentId = selected);
  }

  Future<void> _changeBackground() async {
    const colors = [
      Color(0xfff4f6fb), Color(0xfffff2d8), Color(0xffe8f5e9),
      Color(0xffe3f2fd), Color(0xfff3e5f5), Color(0xff263238),
    ];
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Mind map background'),
        content: Wrap(
          spacing: 10, runSpacing: 10,
          children: colors.map((color) => InkWell(
            onTap: () => Navigator.pop(dialog, color),
            child: CircleAvatar(backgroundColor: color, child: color == _background ? const Icon(Icons.check) : null),
          )).toList(),
        ),
      ),
    );
    if (selected != null) setState(() => _background = selected);
  }

  Future<void> _save() async {
    final controller = TextEditingController(text: widget.note?.title ?? 'Mind map');
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(widget.note == null ? 'Save mind map' : 'Update mind map'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Note title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    final target = widget.note ?? await _notes.create(title: title.trim(), folderId: widget.folderId);
    if (widget.note != null) await _notes.rename(target.id, title.trim());
    final content = <String, Object?>{};
    try {
      final decoded = jsonDecode(target.contentJson ?? '{}');
      if (decoded is Map) content.addAll(decoded.cast<String, Object?>());
    } catch (_) {}
    content.addAll({
      'version': 5,
      'noteType': 'mindmap',
      'mindMap': {'nodes': _nodes, 'edges': _edges, 'background': _background.toARGB32()},
      'pages': <Map<String, Object?>>[],
      'text_delta': const <Map<String, Object?>>[],
    });
    await _notes.saveContent(target.id, content);
    if (mounted) Navigator.pop(context, target);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.note == null ? 'Mind map' : 'Edit mind map'),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Mind map options',
          onSelected: (v) {
            if (v == 'branch') _addNode();
            if (v == 'parent') _chooseParent();
            if (v == 'background') _changeBackground();
            if (v == 'layout') _autoLayout();
            if (v == 'save') _save();
            if (v == 'rename' || v == 'delete') {
              final node = _nodes.firstWhere((item) => item['id']?.toString() == _parentId, orElse: () => _nodes.first);
              if (v == 'rename') _editNode(node); else _deleteBranch(node);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'branch', child: Text('Add child branch')),
            PopupMenuItem(value: 'parent', child: Text('Choose parent for new branches')),
            PopupMenuItem(value: 'background', child: Text('Change background')),
            PopupMenuItem(value: 'layout', child: Text('Auto arrange tree')),
            PopupMenuItem(value: 'rename', child: Text('Rename selected idea')),
            PopupMenuItem(value: 'delete', child: Text('Delete selected branch')),
            PopupMenuItem(value: 'save', child: Text('Save mind map')),
          ],
          icon: const Icon(Icons.account_tree_rounded),
        ),
        IconButton(onPressed: _save, tooltip: 'Save mind map', icon: const Icon(Icons.save_outlined)),
      ],
    ),
    body: ColoredBox(
      color: _background,
      child: InteractiveViewer(
        constrained: false, minScale: .25, maxScale: 3,
        child: SizedBox(
          width: 2200, height: 1600,
          child: Stack(
            children: [
              CustomPaint(size: const Size(2200, 1600), painter: _MindMapLines(_nodes, _edges)),
              for (final node in _nodes)
                Positioned(
                  left: (node['x'] as num).toDouble(),
                  top: (node['y'] as num).toDouble(),
                  child: GestureDetector(
                    onTap: () => setState(() => _parentId = node['id'].toString()),
                    onDoubleTap: () => _editNode(node),
                    onLongPress: () => setState(() => _parentId = node['id'].toString()),
                    onPanUpdate: (d) => setState(() {
                      node['x'] = (node['x'] as num).toDouble() + d.delta.dx;
                      node['y'] = (node['y'] as num).toDouble() + d.delta.dy;
                    }),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: node['id'] == _parentId ? Theme.of(context).colorScheme.tertiaryContainer : Theme.of(context).colorScheme.primaryContainer,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          child: Text(node['text'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addNode, icon: const Icon(Icons.add), label: const Text('Add branch'),
    ),
  );
}

class _MindMapLines extends CustomPainter {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, String>> edges;
  const _MindMapLines(this.nodes, this.edges);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xff8793a3)..strokeWidth = 2.4..style = PaintingStyle.stroke;
    final byId = {for (final n in nodes) n['id'].toString(): n};
    for (final edge in edges) {
      final aNode = byId[edge['from']];
      final bNode = byId[edge['to']];
      if (aNode == null || bNode == null) continue;
      final a = Offset((aNode['x'] as num).toDouble() + 82, (aNode['y'] as num).toDouble() + 28);
      final b = Offset((bNode['x'] as num).toDouble() + 82, (bNode['y'] as num).toDouble() + 28);
      final mid = (a.dx + b.dx) / 2;
      final path = Path()..moveTo(a.dx, a.dy)..cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapLines oldDelegate) => !identical(oldDelegate.nodes, nodes) || !identical(oldDelegate.edges, edges);
}
).firstMatch(node['id']?.toString() ?? '');
          final value = int.tryParse(match?.group(1) ?? '') ?? 0;
          if (value > maxId) maxId = value;
        }
        _counter = maxId + 1;
        _parentId = _nodes.first['id']?.toString() ?? 'root';
      }
    } catch (_) {}
  }

  Future<void> _editNode(Map<String, dynamic> node) async {
    final controller = TextEditingController(text: node['text']?.toString() ?? '');
    final textValue = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Edit idea'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Idea')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('Save idea')),
        ],
      ),
    );
    controller.dispose();
    if (textValue == null || textValue.trim().isEmpty || !mounted) return;
    setState(() => node['text'] = textValue.trim());
  }

  Future<void> _deleteBranch(Map<String, dynamic> node) async {
    final id = node['id']?.toString();
    if (id == null || id == _nodes.first['id']?.toString()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The root idea cannot be deleted.')));
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this branch?'),
        content: const Text('This also removes every nested child of the selected idea.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete branch')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final descendants = <String>{id};
    var expanded = true;
    while (expanded) {
      expanded = false;
      for (final candidate in _nodes) {
        final candidateId = candidate['id']?.toString();
        final parentId = candidate['parentId']?.toString();
        if (candidateId != null && parentId != null &&
            descendants.contains(parentId) && descendants.add(candidateId)) {
          expanded = true;
        }
      }
    }
    setState(() {
      _nodes.removeWhere((item) => descendants.contains(item['id']?.toString()));
      _edges.removeWhere((edge) => descendants.contains(edge['from']) || descendants.contains(edge['to']));
      if (descendants.contains(_parentId)) _parentId = _nodes.first['id']?.toString() ?? 'root';
    });
  }

  void _autoLayout() {
    if (_nodes.isEmpty) return;
    final children = <String, List<Map<String, dynamic>>>{};
    for (final node in _nodes) {
      final id = node['id']?.toString();
      final parent = node['parentId']?.toString();
      if (id != null && parent != null) {
        (children[parent] ??= <Map<String, dynamic>>[]).add(node);
      }
    }
    double nextLeafY = 80;
    final visited = <String>{};
    double place(Map<String, dynamic> node, int depth) {
      final id = node['id']?.toString() ?? '';
      if (!visited.add(id)) return (node['y'] as num?)?.toDouble() ?? nextLeafY;
      final kids = children[id] ?? const <Map<String, dynamic>>[];
      double y;
      if (kids.isEmpty) {
        y = nextLeafY;
        nextLeafY += 126;
      } else {
        final centers = kids.map((child) => place(child, depth + 1)).toList();
        y = (centers.first + centers.last) / 2;
      }
      node['x'] = 100.0 + depth * 270.0;
      node['y'] = y;
      return y;
    }
    setState(() {
      place(_nodes.first, 0);
    });
  }

  Future<void> _addNode() async {
    final c = TextEditingController(text: 'New idea');
    final textValue = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Add child branch'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Idea')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Add branch')),
        ],
      ),
    );
    c.dispose();
    if (textValue == null || textValue.trim().isEmpty) return;
    setState(() {
      final parent = _nodes.firstWhere((n) => n['id'] == _parentId, orElse: () => _nodes.first);
      final siblings = _edges.where((e) => e['from'] == _parentId).length;
      final id = 'node' + (_counter++).toString();
      final px = (parent['x'] as num).toDouble();
      final py = (parent['y'] as num).toDouble();
      _nodes.add({
        'id': id, 'parentId': _parentId, 'text': textValue.trim(),
        'x': px + 260.0, 'y': py + (siblings - .5) * 115.0,
      });
      _edges.add({'from': _parentId, 'to': id});
    });
  }

  Future<void> _chooseParent() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Choose parent idea'),
        children: _nodes.map((node) => SimpleDialogOption(
          onPressed: () => Navigator.pop(dialog, node['id'].toString()),
          child: Text(node['text'].toString()),
        )).toList(),
      ),
    );
    if (selected != null) setState(() => _parentId = selected);
  }

  Future<void> _changeBackground() async {
    const colors = [
      Color(0xfff4f6fb), Color(0xfffff2d8), Color(0xffe8f5e9),
      Color(0xffe3f2fd), Color(0xfff3e5f5), Color(0xff263238),
    ];
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Mind map background'),
        content: Wrap(
          spacing: 10, runSpacing: 10,
          children: colors.map((color) => InkWell(
            onTap: () => Navigator.pop(dialog, color),
            child: CircleAvatar(backgroundColor: color, child: color == _background ? const Icon(Icons.check) : null),
          )).toList(),
        ),
      ),
    );
    if (selected != null) setState(() => _background = selected);
  }

  Future<void> _save() async {
    final c = TextEditingController(text: 'Mind map');
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Save mind map'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Note title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (title == null || title.trim().isEmpty) return;
    final note = await _notes.create(title: title.trim(), folderId: widget.folderId);
    await _notes.saveContent(note.id, {
      'version': 5,
      'noteType': 'mindmap',
      'mindMap': {'nodes': _nodes, 'edges': _edges, 'background': _background.toARGB32()},
      'pages': <Map<String, Object?>>[],
      'text_delta': const <Map<String, Object?>>[],
    });
    if (mounted) Navigator.pop(context, note);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mind map'),
      actions: [
        PopupMenuButton<String>(
          tooltip: 'Mind map options',
          onSelected: (v) {
            if (v == 'branch') _addNode();
            if (v == 'parent') _chooseParent();
            if (v == 'background') _changeBackground();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'branch', child: Text('Add child branch')),
            PopupMenuItem(value: 'parent', child: Text('Choose parent idea')),
            PopupMenuItem(value: 'background', child: Text('Change background')),
          ],
          icon: const Icon(Icons.account_tree_rounded),
        ),
        IconButton(onPressed: _save, tooltip: 'Save mind map', icon: const Icon(Icons.save_outlined)),
      ],
    ),
    body: ColoredBox(
      color: _background,
      child: InteractiveViewer(
        constrained: false, minScale: .25, maxScale: 3,
        child: SizedBox(
          width: 2200, height: 1600,
          child: Stack(
            children: [
              CustomPaint(size: const Size(2200, 1600), painter: _MindMapLines(_nodes, _edges)),
              for (final node in _nodes)
                Positioned(
                  left: (node['x'] as num).toDouble(),
                  top: (node['y'] as num).toDouble(),
                  child: GestureDetector(
                    onLongPress: () => setState(() => _parentId = node['id'].toString()),
                    onPanUpdate: (d) => setState(() {
                      node['x'] = (node['x'] as num).toDouble() + d.delta.dx;
                      node['y'] = (node['y'] as num).toDouble() + d.delta.dy;
                    }),
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(16),
                      color: node['id'] == _parentId ? Theme.of(context).colorScheme.tertiaryContainer : Theme.of(context).colorScheme.primaryContainer,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 190),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          child: Text(node['text'].toString(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _addNode, icon: const Icon(Icons.add), label: const Text('Add branch'),
    ),
  );
}

class _MindMapLines extends CustomPainter {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, String>> edges;
  const _MindMapLines(this.nodes, this.edges);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xff8793a3)..strokeWidth = 2.4..style = PaintingStyle.stroke;
    final byId = {for (final n in nodes) n['id'].toString(): n};
    for (final edge in edges) {
      final aNode = byId[edge['from']];
      final bNode = byId[edge['to']];
      if (aNode == null || bNode == null) continue;
      final a = Offset((aNode['x'] as num).toDouble() + 82, (aNode['y'] as num).toDouble() + 28);
      final b = Offset((bNode['x'] as num).toDouble() + 82, (bNode['y'] as num).toDouble() + 28);
      final mid = (a.dx + b.dx) / 2;
      final path = Path()..moveTo(a.dx, a.dy)..cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapLines oldDelegate) => !identical(oldDelegate.nodes, nodes) || !identical(oldDelegate.edges, edges);
}
