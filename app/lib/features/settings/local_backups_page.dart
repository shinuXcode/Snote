import 'package:flutter/material.dart';

import '../../data/local/note_repository.dart';
import '../../data/local/notebook_transfer_service.dart';

/// Local encrypted notebook backup and restore controls.
class LocalBackupsPage extends StatefulWidget {
  const LocalBackupsPage({super.key});

  @override
  State<LocalBackupsPage> createState() => _LocalBackupsPageState();
}

class _LocalBackupsPageState extends State<LocalBackupsPage> {
  bool _busy = false;

  Future<String?> _askPassword({required bool restoring}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(restoring ? 'Restore encrypted backup' : 'Create encrypted backup'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Backup password',
            helperText: 'Use at least 8 characters. Keep it safe; it cannot be recovered.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(restoring ? 'Choose backup' : 'Save backup'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.length < 8) return null;
    return result;
  }

  Future<void> _run({required bool restoring}) async {
    final password = await _askPassword(restoring: restoring);
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final transfer = NotebookTransferService(NoteRepository());
      if (restoring) {
        final count = await transfer.importEncryptedPicked(password: password);
        if (mounted && count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Restored $count note(s) and their available attachments.')),
          );
        }
      } else {
        final path = await transfer.exportEncryptedPicked(password: password);
        if (mounted && path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Encrypted backup saved.')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup operation failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Local Backups')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            shrinkWrap: true,
            children: [
              Icon(Icons.backup_rounded, size: 54, color: colors.primary),
              const SizedBox(height: 18),
              Text(
                'Keep a private copy of your notebook',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Encrypted backups include visible notes, folder structure, page content, and attached files such as source PDFs. Existing older encrypted backups remain importable.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(restoring: false),
                icon: const Icon(Icons.lock_rounded),
                label: const Text('Create encrypted backup'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(restoring: true),
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Restore encrypted backup'),
              ),
              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
