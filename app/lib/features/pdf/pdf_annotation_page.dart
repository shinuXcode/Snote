import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';

class PdfAnnotationPage extends StatefulWidget {
  const PdfAnnotationPage({super.key});

  @override
  State<PdfAnnotationPage> createState() => _PdfAnnotationPageState();
}

class _PdfAnnotationPageState extends State<PdfAnnotationPage> {
  PdfControllerPinch? _controller;
  Uint8List? _bytes;

  Future<void> _openPdf() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (file == null) return;

    final bytes = await file.readAsBytes();
    final future = PdfDocument.openData(bytes);

    if (future == null) return;

    setState(() {
      _bytes = bytes;
      _controller = PdfControllerPinch(document: future);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF annotation'),
        actions: [
          IconButton(
            tooltip: 'Open PDF',
            onPressed: _openPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: controller == null
          ? Center(
              child: FilledButton.icon(
                onPressed: _openPdf,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Choose PDF'),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: PdfViewPinch(
                    controller: controller,
                    scrollDirection: Axis.vertical,
                  ),
                ),
                Positioned(
                  right: 18,
                  bottom: 18,
                  child: Card(
                    child: SizedBox(
                      width: 300,
                      height: 360,
                      child: SnoteCanvas(
                        pen: const PenConfig(
                          type: PenType.ballpoint,
                          color: Colors.indigo,
                          size: 3,
                        ),
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ),
                ),
                if (_bytes != null)
                  Positioned(
                    left: 18,
                    bottom: 18,
                    child: const Chip(
                      label: Text('PDF loaded locally'),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
