import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/local/note_repository.dart';

class QrImportPage extends StatefulWidget {
  const QrImportPage({super.key});

  @override
  State<QrImportPage> createState() => _QrImportPageState();
}

class _QrImportPageState extends State<QrImportPage> {
  final Map<int, String> _chunks = {};
  String? _transferId;
  int? _total;
  bool _importing = false;

  bool get _cameraSupported => kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  Future<void> _consume(String raw) async {
    if (_importing) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Invalid Snote QR payload.');
      final format = decoded['format']?.toString();

      if (format == 'snote-note-v1') {
        await _saveNote(decoded.cast<String, dynamic>());
        return;
      }

      if (format != 'snote-qr-v2') {
        throw const FormatException('Not an Snote transfer QR.');
      }

      final transferId = decoded['transfer_id']?.toString();
      final index = (decoded['index'] as num?)?.toInt();
      final total = (decoded['total'] as num?)?.toInt();
      final data = decoded['data']?.toString();
      if (transferId == null || index == null || total == null || data == null || total < 1 || index < 0 || index >= total) {
        throw const FormatException('Invalid Snote QR frame.');
      }

      if (_transferId != transferId) {
        _chunks.clear();
        _transferId = transferId;
        _total = total;
      }
      _chunks[index] = data;
      if (mounted) setState(() {});

      if (_chunks.length == total && _chunks.keys.every((i) => i >= 0 && i < total)) {
        final payload = List.generate(total, (i) => _chunks[i]).join();
        final note = jsonDecode(payload);
        if (note is! Map) throw const FormatException('Invalid assembled note.');
        await _saveNote(note.cast<String, dynamic>());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _saveNote(Map<String, dynamic> decoded) async {
    _importing = true;
    try {
      final content = decoded['content'];
      final title = decoded['title']?.toString() ?? 'Imported note';
      final repo = NoteRepository();
      final note = await repo.create(title: title);
      if (content is Map) {
        await repo.saveContent(note.id, content.cast<String, Object?>());
      }
      _chunks.clear();
      _transferId = null;
      _total = null;
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note imported successfully.')));
      }
    } finally {
      _importing = false;
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json', 'snote'], withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    try {
      await _consume(utf8.decode(bytes));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total == null || _total == 0 ? 0 : _chunks.length / _total!;
    return Scaffold(
      appBar: AppBar(title: const Text('Import transfer')),
      body: Column(
        children: [
          if (_cameraSupported)
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(onDetect: (capture) {
                    for (final barcode in capture.barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.isNotEmpty) _consume(raw);
                    }
                  }),
                  Center(child: Container(width: 260, height: 260, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(24)))),
                  Positioned(left: 20, right: 20, bottom: 24, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Point the camera at an Snote QR transfer.'),
                    if (_total != null) ...[const SizedBox(height: 10), LinearProgressIndicator(value: progress), const SizedBox(height: 6), Text('Scanned ${_chunks.length} / ${_total!} frames')],
                  ])))),
                ],
              ),
            )
          else
            const Expanded(child: Center(child: Text('Camera scanning is unavailable on this platform.'))),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(onPressed: _importing ? null : _pickFile, icon: const Icon(Icons.file_open_rounded), label: const Text('Import transfer file instead')),
            ),
          ),
        ],
      ),
    );
  }
}