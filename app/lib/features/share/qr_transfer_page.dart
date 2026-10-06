import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/local/note_repository.dart';
import '../../canvas_engine/models/stroke_codec.dart';

class QrTransferPage extends StatelessWidget {
  final LocalNote note;

  const QrTransferPage({
    super.key,
    required this.note,
  });

  @override
  Widget build(BuildContext context) {
    final payload = jsonEncode({
      'format': 'snote-note-v1',
      'id': note.id,
      'title': note.title,
      'content': note.contentJson == null
          ? StrokeCodec.strokesToDocument(const [])
          : jsonDecode(note.contentJson!),
    });

    return Scaffold(
      appBar: AppBar(title: const Text('QR note transfer')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Show this QR code on the receiving Snote device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: QrImageView(
                    data: payload,
                    size: 280,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                note.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'QR generation is local-only; nothing is uploaded.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
