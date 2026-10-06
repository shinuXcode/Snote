import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../canvas_engine/models/stroke_codec.dart';
import '../../data/local/note_repository.dart';

class QrTransferPage extends StatefulWidget {
  final LocalNote note;
  const QrTransferPage({super.key, required this.note});

  @override
  State<QrTransferPage> createState() => _QrTransferPageState();
}

class _QrTransferPageState extends State<QrTransferPage> {
  static const _chunkSize = 900;
  Timer? _timer;
  late final List<String> _chunks;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    final payload = jsonEncode({
      'format': 'snote-note-v2',
      'id': widget.note.id,
      'title': widget.note.title,
      'content': widget.note.contentJson == null
          ? StrokeCodec.strokesToDocument(const [])
          : jsonDecode(widget.note.contentJson!),
    });
    _chunks = [
      for (var start = 0; start < payload.length; start += _chunkSize)
        payload.substring(start, (start + _chunkSize).clamp(0, payload.length)),
    ];
    if (_chunks.length > 1) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _chunks.length);
    });
  }

  String get _qrPayload => jsonEncode({
        'format': 'snote-qr-v2',
        'transfer_id': widget.note.id,
        'index': _index,
        'total': _chunks.length,
        'data': _chunks[_index],
      });

  @override
  Widget build(BuildContext context) {
    final total = _chunks.length;
    final running = _timer?.isActive == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR note transfer'),
        actions: [
          if (total > 1)
            IconButton(
              tooltip: running ? 'Pause' : 'Resume',
              onPressed: () {
                if (running) {
                  _timer?.cancel();
                } else {
                  _startTimer();
                }
                setState(() {});
              },
              icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                total == 1
                    ? 'Scan this QR code on the receiving Snote device.'
                    : 'Keep this screen visible. The QR sequence advances automatically.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: QrImageView(
                    data: _qrPayload,
                    size: 300,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('${_index + 1} / $total', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(widget.note.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                total == 1
                    ? 'Local-only transfer. Nothing is uploaded.'
                    : 'Scan all frames. The receiver assembles the note automatically.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}