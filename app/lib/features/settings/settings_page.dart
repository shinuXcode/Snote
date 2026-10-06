import 'package:flutter/material.dart';

import '../../app/theme_controller.dart';
import '../../core/security/note_lock_service.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../data/local/note_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _theme = SnoteThemeController.instance;
  final _lock = NoteLockService();
  bool _eInk = SnoteThemeController.instance.eInk;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Snote settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: SwitchListTile(
              value: _eInk,
              onChanged: (value) async {
                await _theme.setEInk(value);
                if (mounted) setState(() => _eInk = value);
              },
              title: const Text('E-Ink / eye-comfort mode'),
              subtitle: const Text(
                'Reduce color contrast and use a paper-like, high-contrast palette.',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.fingerprint_rounded),
              title: const Text('Biometric note lock'),
              subtitle: const Text(
                'Lock individual notes with the device authentication system.',
              ),
              onTap: () async {
                final ok = await _lock.authenticate();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Authentication is available.' : 'Authentication unavailable.'),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.import_export_rounded),
              title: const Text('Import / export notebook'),
              subtitle: const Text('Move your notes as portable Snote JSON.'),
              onTap: () async {
                final transfer = NotebookTransferService(NoteRepository());
                final choice = await showModalBottomSheet<String>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ListTile(
                          leading: const Icon(Icons.upload_file_rounded),
                          title: const Text('Import JSON'),
                          onTap: () => Navigator.pop(context, 'import'),
                        ),
                        ListTile(
                          leading: const Icon(Icons.download_rounded),
                          title: const Text('Export JSON'),
                          onTap: () => Navigator.pop(context, 'export'),
                        ),
                      ],
                    ),
                  ),
                );

                try {
                  if (choice == 'import') {
                    final count = await transfer.importFromPickedFile();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Imported ' + count.toString() + ' notes.')),
                      );
                    }
                  } else if (choice == 'export') {
                    final payload = await transfer.exportAll();
                    await showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Notebook JSON'),
                        content: SelectableText(payload),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
