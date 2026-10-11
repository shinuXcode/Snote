import 'dart:convert';
import 'dart:ui' as ui;

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
  final List<Map<String, dynamic>> _nodes = <Map<String, dynamic>>[
    <String, dynamic>{'id': 'root', 'parentId': null, 'text': 'Main idea', 'x': 100.0, 'y': 280.0},
  ];
  final List<Map<String, String>> _edges = <Map<String, String>>[];
  int _counter = 1;
  String _parentId = 'root';
  Color _background = const Color(0xfff4f6fb);

  @override
  void initState() {
    super.initState();
    _loadExistingMap();
  }

  void _loadExistingMap() {
    try {
      final decoded = jsonDecode(widget.note?.contentJson ?? '{}');
      if (decoded is! Map || decoded['mindMap'] is! Map) return;
      final map = decoded['mindMap'] as Map;
      final rawNodes = map['nodes'];
      if (rawNodes is List) {
        final loaded = <Map<String, dynamic>>[];
        var generatedId = 1;
        for (final rawNode in rawNodes) {
          if (rawNode is! Map) continue;
          final node = Map<String, dynamic>.from(rawNode);
          node['id'] = (node['id'] ?? ('node' + generatedId.toString())).toString();
          node['text'] = (node['text'] ?? 'Idea').toString();
          node['x'] = (node['x'] is num ? (node['x'] as num).toDouble() : 100.0);
          node['y'] = (node['y'] is num ? (node['y'] as num).toDouble() : 100.0);
          loaded.add(node);
          generatedId++;
        }
        if (loaded.isNotEmpty) {
          _nodes
            ..clear()
            ..addAll(loaded);
        }
      }
      final rawEdges = map['edges'];
      if (rawEdges is List) {
        _edges
          ..clear()
          ..addAll(rawEdges.whereType<Map>().map((rawEdge) => <String, String>{
            'from': (rawEdge['from'] ?? '').toString(),
            'to': (rawEdge['to'] ?? '').toString(),
          }));
      }
      final background = map['background'];
      if (background is num) _background = Color(background.toInt());
      var maxId = 0;
      for (final node in _nodes) {
        final id = (node['id'] ?? '').toString();
        if (id.startsWith('node')) {
          final number = int.tryParse(id.substring(4)) ?? 0;
          if (number > maxId) maxId = number;
        }
      }
      _counter = maxId + 1;
      final root = _nodes.firstWhere(
        (node) => node['parentId'] == null,
        orElse: () => _nodes.first,
      );
      _parentId = (root['id'] ?? 'root').toString();
    } catch (_) {
      // Keep the safe default map if saved JSON is malformed.
    }
  }

  Future<void> _addNode() async {
    final controller = TextEditingController(text: 'New idea');
    final textValue = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Add child branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Idea'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('Add branch')),
        ],
      ),
    );
    controller.dispose();
    if (textValue == null || textValue.trim().isEmpty || !mounted) return;
    setState(() {
      final parent = _nodes.firstWhere(
        (node) => node['id'].toString() == _parentId,
        orElse: () => _nodes.first,
      );
      final siblings = _edges.where((edge) => edge['from'] == _parentId).length;
      final id = 'node' + (_counter++).toString();
      final parentX = (parent['x'] as num).toDouble();
      final parentY = (parent['y'] as num).toDouble();
      _nodes.add(<String, dynamic>{
        'id': id,
        'parentId': _parentId,
        'text': textValue.trim(),
        'x': parentX + 270.0,
        'y': parentY + (siblings - .5) * 125.0,
      });
      _edges.add(<String, String>{'from': _parentId, 'to': id});
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
    if (selected != null && mounted) setState(() => _parentId = selected);
  }

  Future<void> _editNode(Map<String, dynamic> node) async {
    final controller = TextEditingController(text: node['text']?.toString() ?? '');
    final textValue = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Edit idea'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Idea'),
        ),
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
        content: const Text('This also removes all nested child ideas.'),
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

  Future<void> _changeBackground() async {
    const colors = <Color>[
      Color(0xfff4f6fb),
      Color(0xfffff2d8),
      Color(0xffe8f5e9),
      Color(0xffe3f2fd),
      Color(0xfff3e5f5),
      Color(0xff263238),
      Color(0xfffbe9e7),
      Color(0xffe0f7fa),
      Color(0xfffff9c4),
      Color(0xffede7f6),
    ];
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Mind map background'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((color) => InkWell(
            onTap: () => Navigator.pop(dialog, color),
            child: CircleAvatar(
              backgroundColor: color,
              child: color == _background ? const Icon(Icons.check) : null,
            ),
          )).toList(),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _background = selected);
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

  Future<void> _save() async {
    final controller = TextEditingController(text: widget.note?.title ?? 'Mind map');
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(widget.note == null ? 'Save mind map' : 'Update mind map'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Note title'),
        ),
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
          onSelected: (value) {
            if (value == 'branch') _addNode();
            if (value == 'parent') _chooseParent();
            if (value == 'background') _changeBackground();
            if (value == 'layout') _autoLayout();
            if (value == 'save') _save();
            if (value == 'rename' || value == 'delete') {
              final node = _nodes.firstWhere(
                (item) => item['id']?.toString() == _parentId,
                orElse: () => _nodes.first,
              );
              if (value == 'rename') _editNode(node); else _deleteBranch(node);
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
        constrained: false,
        minScale: .25,
        maxScale: 3,
        child: SizedBox(
          width: 2600,
          height: 1800,
          child: Stack(
            children: [
              CustomPaint(size: const Size(2600, 1800), painter: _MindMapGrid(_background)),
              CustomPaint(size: const Size(2600, 1800), painter: _MindMapLines(_nodes, _edges)),
              for (final node in _nodes)
                Positioned(
                  left: (node['x'] as num).toDouble(),
                  top: (node['y'] as num).toDouble(),
                  child: GestureDetector(
                    onTap: () => setState(() => _parentId = node['id'].toString()),
                    onDoubleTap: () => _editNode(node),
                    onLongPress: () => setState(() => _parentId = node['id'].toString()),
                    onPanUpdate: (details) => setState(() {
                      node['x'] = (node['x'] as num).toDouble() + details.delta.dx;
                      node['y'] = (node['y'] as num).toDouble() + details.delta.dy;
                    }),
                    child: Material(
                      elevation: node['id'] == _parentId ? 8 : 3,
                      borderRadius: BorderRadius.circular(16),
                      color: node['id'] == _parentId
                          ? Theme.of(context).colorScheme.tertiaryContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 210),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                          child: Text(
                            node['text'].toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
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
      onPressed: _addNode,
      icon: const Icon(Icons.add),
      label: const Text('Add branch'),
    ),
  );
}

class _MindMapLines extends CustomPainter {
  final List<Map<String, dynamic>> nodes;
  final List<Map<String, String>> edges;

  const _MindMapLines(this.nodes, this.edges);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff8793a3)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    final byId = {for (final node in nodes) node['id'].toString(): node};
    for (final edge in edges) {
      final parent = byId[edge['from']];
      final child = byId[edge['to']];
      if (parent == null || child == null) continue;
      final a = Offset((parent['x'] as num).toDouble() + 86, (parent['y'] as num).toDouble() + 30);
      final b = Offset((child['x'] as num).toDouble() + 86, (child['y'] as num).toDouble() + 30);
      final mid = (a.dx + b.dx) / 2;
      final path = Path()..moveTo(a.dx, a.dy)..cubicTo(mid, a.dy, mid, b.dy, b.dx, b.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapLines oldDelegate) =>
      !identical(oldDelegate.nodes, nodes) || !identical(oldDelegate.edges, edges);
}

class _MindMapGrid extends CustomPainter {
  final Color background;
  const _MindMapGrid(this.background);

  @override
  void paint(Canvas canvas, Size size) {
    final light = background.computeLuminance() > .45;
    final paint = Paint()
      ..color = (light ? Colors.blueGrey.shade300 : Colors.white).withValues(alpha: .34)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final points = <Offset>[];
    for (double x = 28; x < size.width; x += 28) {
      for (double y = 28; y < size.height; y += 28) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(ui.PointMode.points, points, paint);
  }

  @override
  bool shouldRepaint(covariant _MindMapGrid oldDelegate) => oldDelegate.background != background;
}
