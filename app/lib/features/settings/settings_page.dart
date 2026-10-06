import 'package:flutter/material.dart';
import '../../app/theme_controller.dart';
import '../../core/security/note_lock_service.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../data/local/note_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _theme = SnoteThemeController.instance;
  final _lock = NoteLockService();
  bool _eInk = SnoteThemeController.instance.eInk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 32),
        children: [
          _SectionTitle('Appearance'),
          Card(child: Column(children: [
            SwitchListTile.adaptive(
              value: _eInk,
              onChanged: (v) async { await _theme.setEInk(v); if (mounted) setState(() => _eInk = v); },
              secondary: CircleAvatar(backgroundColor: scheme.primaryContainer, child: Icon(Icons.auto_awesome_rounded, color: scheme.primary)),
              title: const Text('Paper comfort mode', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('A softer paper palette for long writing sessions.'),
            ),
          ])),
          const SizedBox(height: 18),
          _SectionTitle('Privacy & security'),
          Card(child: Column(children: [
            ListTile(
              leading: CircleAvatar(backgroundColor: scheme.secondaryContainer, child: const Icon(Icons.fingerprint_rounded)),
              title: const Text('Biometric note lock', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Protect individual notes with device authentication.'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await _lock.authenticate();
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text(ok ? 'Device authentication is available.' : 'Authentication is unavailable.')));
              },
            ),
          ])),
          const SizedBox(height: 18),
          _SectionTitle('Notebook'),
          Card(child: ListTile(
            leading: CircleAvatar(backgroundColor: scheme.tertiaryContainer, child: const Icon(Icons.import_export_rounded)),
            title: const Text('Import / export notebook', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Move your notes as portable Snote JSON.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _transfer,
          )),
          const SizedBox(height: 18),
          _SectionTitle('About'),
          Card(child: Column(children: [
            ListTile(leading: const Icon(Icons.info_outline_rounded), title: const Text('About Snote', style: TextStyle(fontWeight: FontWeight.w800)), subtitle: const Text('Offline-first handwriting and rich-text notebook.'), onTap: () => showAboutDialog(context: context, applicationName: 'Snote', applicationVersion: '0.4.0', applicationLegalese: 'Private, local-first notes.')),
            const Divider(height: 1),
            const ListTile(leading: Icon(Icons.verified_outlined), title: Text('Build 0.4.0', style: TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('Cross-platform Flutter build')),
          ])),
        ],
      ),
    );
  }

  Future<void> _transfer() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final transfer = NotebookTransferService(NoteRepository());
    final choice = await showModalBottomSheet<String>(
      context: context, showDragHandle: true,
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.upload_file_rounded), title: const Text('Import JSON'), onTap: () => Navigator.pop(context, 'import')),
        ListTile(leading: const Icon(Icons.download_rounded), title: const Text('Export JSON'), onTap: () => Navigator.pop(context, 'export')),
      ])),
    );
    try {
      if (choice == 'import') {
        final count = await transfer.importFromPickedFile();
        if (mounted) messenger.showSnackBar(SnackBar(content: Text('Imported $count notes.')));
      } else if (choice == 'export') {
        final payload = await transfer.exportAll();
        if (!mounted) return;
        await navigator.push(MaterialPageRoute(builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Notebook export')),
          body: SelectableText(payload, style: const TextStyle(fontFamily: 'monospace')),
        )));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(text.toUpperCase(), style: TextStyle(fontSize: 12, letterSpacing: 1.1, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
  );
}
