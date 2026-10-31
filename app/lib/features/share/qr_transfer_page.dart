import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/local/folder_repository.dart';
import '../../data/local/note_repository.dart';
import '../../data/local/notebook_transfer_service.dart';

class QrTransferPage extends StatefulWidget {
  final LocalNote? note;
  final LocalFolder? folder;
  const QrTransferPage({super.key, this.note, this.folder})
      : assert((note == null) != (folder == null));

  @override
  State<QrTransferPage> createState() => _QrTransferPageState();
}

class _QrTransferPageState extends State<QrTransferPage> {
  static const _chunkSize = 1200;
  final String _transferId = DateTime.now().microsecondsSinceEpoch.toString();
  Timer? _timer;
  List<String> _chunks = <String>[];
  int _index = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_prepareEncryptedTransfer()));
  }

  Future<String?> _askPassword() async {
    final controller = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Encrypt QR transfer'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Transfer password',
            helperText: 'Enter the same password on the receiving device. Use at least 8 characters.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.length >= 8) Navigator.pop(dialogContext, controller.text);
            },
            child: const Text('Encrypt'),
          ),
        ],
      ),
    );
    controller.dispose();
    return password;
  }

  Future<void> _prepareEncryptedTransfer() async {
    try {
      final password = await _askPassword();
      if (!mounted) return;
      if (password == null) {
        Navigator.of(context).pop();
        return;
      }
      final encryptedBytes = await NotebookTransferService(NoteRepository())
          .exportEncryptedArchiveBytes(
        password: password,
        folderId: widget.folder?.id,
        noteId: widget.note?.id,
      );
      if (encryptedBytes.length > 128 * 1024) {
        throw StateError(
          'This selection is too large for a reliable QR transfer (128 KB limit). '
          'Use the encrypted Snote backup file for large PDFs or attachments.',
        );
      }
      final payload = base64Encode(encryptedBytes);
      if (!mounted) return;
      setState(() {
        _chunks = [
          for (var start = 0; start < payload.length; start += _chunkSize)
            payload.substring(start, (start + _chunkSize).clamp(0, payload.length)),
        ];
        _loading = false;
        _error = null;
      });
      if (_chunks.length > 1) _startTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1400), (_) {
      if (mounted) setState(() => _index = (_index + 1) % _chunks.length);
    });
  }

  String get _qrPayload => jsonEncode({
        'format': 'snote-qr-v2',
        'transfer_id': _transferId,
        'index': _index,
        'total': _chunks.length,
        'data': _chunks[_index],
      });

  @override
  Widget build(BuildContext context) {
    final total = _chunks.length;
    final running = _timer?.isActive == true;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR note transfer')),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Encrypted QR transfer'),
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
                    ? 'Scan this QR code on the receiving Snotee device.'
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
              Text(widget.note?.title ?? widget.folder!.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(
                total == 1
                    ? 'Encrypted local transfer. Enter the same password on the receiving device.'
                    : 'Scan all frames. The receiver decrypts this selection, including its folders, pages and attachments. Keep the password private and share it separately.',
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