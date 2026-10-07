import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';

class MindMapPage extends StatefulWidget {
  final String? folderId;
  const MindMapPage({super.key, this.folderId});

  @override
  State<MindMapPage> createState() => _MindMapPageState();
}

class _MindMapPageState extends State<MindMapPage> {
  final _notes = NoteRepository();
  final List<Map<String, dynamic>> _nodes = [
    {'id': 'root', 'text': 'Main idea', 'x': 320.0, 'y': 240.0},
  ];
  int _counter = 1;

  Future<void> _addNode() async {
    final c = TextEditingController(text: 'New node');
    final textValue = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Add node'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Add')),
        ],
      ),
    );
    c.dispose();
    if (textValue == null || textValue.trim().isEmpty) return;
    setState(() {
      final i = _counter++;
      _nodes.add({'id': 'n$i', 'text': textValue.trim(), 'x': 120.0 + (i % 3) * 190.0, 'y': 110.0 + (i % 4) * 120.0});
    });
  }

  Future<void> _save() async {
    final title = await showDialog<String>(
      context: context,
      builder: (dialog) {
        final c = TextEditingController(text: 'Mind map');
        return AlertDialog(
          title: const Text('Save mind map'),
          content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Note title')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, c.text), child: const Text('Save')),
          ],
        );
      },
    );
    if (title == null || title.trim().isEmpty) return;
    final note = await _notes.create(title: title.trim(), folderId: widget.folderId);
    await _notes.saveContent(note.id, {
      'version': 5,
      'noteType': 'mindmap',
      'mindMap': {'nodes': _nodes, 'edges': const <Map<String, String>>[]},
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
            IconButton(onPressed: _addNode, tooltip: 'Add node', icon: const Icon(Icons.add_circle_outline)),
            IconButton(onPressed: _save, tooltip: 'Save', icon: const Icon(Icons.save_outlined)),
          ],
        ),
        body: InteractiveViewer(
          constrained: false,
          minScale: .35,
          maxScale: 3,
          child: SizedBox(
            width: 900,
            height: 650,
            child: Stack(
              children: [
                CustomPaint(size: const Size(900, 650), painter: _MindMapLines(_nodes)),
                for (final node in _nodes)
                  Positioned(
                    left: (node['x'] as num).toDouble(),
                    top: (node['y'] as num).toDouble(),
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        node['x'] = (node['x'] as num).toDouble() + d.delta.dx;
                        node['y'] = (node['y'] as num).toDouble() + d.delta.dy;
                      }),
                      child: Material(
                        elevation: 2,
                        borderRadius: BorderRadius.circular(18),
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          child: Text(node['text'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

class _MindMapLines extends CustomPainter {
  final List<Map<String, dynamic>> nodes;
  const _MindMapLines(this.nodes);

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.length < 2) return;
    final paint = Paint()..color = const Color(0xff9aa0ac)..strokeWidth = 2;
    final root = Offset((nodes.first['x'] as num).toDouble() + 65, (nodes.first['y'] as num).toDouble() + 25);
    for (final node in nodes.skip(1)) {
      final p = Offset((node['x'] as num).toDouble() + 65, (node['y'] as num).toDouble() + 25);
      canvas.drawLine(root, p, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MindMapLines oldDelegate) => !identical(oldDelegate.nodes, nodes);
}
