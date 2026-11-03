import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sync_journal.dart';

/// Beta status page: local journal is active; remote transports are not enabled yet.
class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({super.key});
  @override State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  SyncJournalStatus? _status;
  Object? _error;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final status = await SyncJournal.status();
      if (!mounted) return;
      setState(() { _status = status; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error; _loading = false; });
    }
  }

  Future<void> _copyDeviceId() async {
    final id = _status?.deviceId;
    if (id == null) return;
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device ID copied')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync & Devices'), actions: [
        IconButton(tooltip: 'Refresh status', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded)),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
          Card(child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.devices_rounded, color: colors.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Local-first synchronization', style: TextStyle(fontWeight: FontWeight.w800))),
                const Chip(label: Text('Beta foundation')),
              ]),
              const SizedBox(height: 12),
              Text('Notes continue to save locally. The change journal is ready for encrypted device-to-device and cloud-provider transports.', style: TextStyle(color: colors.onSurfaceVariant)),
              const SizedBox(height: 12),
              if (_loading) const LinearProgressIndicator()
              else if (_error != null) Text('Could not read sync status: ' + _error.toString(), style: TextStyle(color: colors.error))
              else Row(children: [
                Icon(Icons.check_circle_outline, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Local journal available')),
              ]),
            ]),
          )),
          const SizedBox(height: 12),
          _sectionTitle(context, 'This device'),
          Card(child: Column(children: [
            ListTile(
              leading: const Icon(Icons.fingerprint_rounded), title: const Text('Device identity'),
              subtitle: Text(_status?.deviceId ?? 'Preparing local identity…', maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(tooltip: 'Copy device ID', onPressed: _status == null ? null : _copyDeviceId, icon: const Icon(Icons.copy_rounded)),
            ),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.pending_actions_rounded), title: const Text('Pending local changes'), trailing: Text((_status?.pendingOperations ?? 0).toString())),
            const Divider(height: 1),
            ListTile(leading: const Icon(Icons.numbers_rounded), title: const Text('Local change sequence'), trailing: Text((_status?.lastSequence ?? 0).toString())),
          ])),
          const SizedBox(height: 12),
          _sectionTitle(context, 'Synchronization methods'),
          _providerTile(context, icon: Icons.wifi_rounded, title: 'Nearby device sync', subtitle: 'Local Wi-Fi pairing and encrypted transfer', status: 'Not connected'),
          _providerTile(context, icon: Icons.cloud_outlined, title: 'Google Drive', subtitle: 'Encrypted appDataFolder adapter ready; OAuth setup pending', status: 'Not configured'),
          _providerTile(context, icon: Icons.folder_shared_outlined, title: 'WebDAV', subtitle: 'HTTPS object transport ready; connection setup pending', status: 'Not configured'),
          _providerTile(context, icon: Icons.hub_outlined, title: 'Internet peer-to-peer', subtitle: 'Direct connection where network conditions allow', status: 'Not available yet'),
          const SizedBox(height: 12),
          Card(color: colors.surfaceContainerLow, child: const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Drive and WebDAV storage adapters are implemented, but account setup and the encrypted change-pack/apply pipeline are not connected yet. No note data is uploaded by this beta. Existing local notes, QR transfer and encrypted local backup continue to work independently.'),
          )),
        ]),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
  );

  Widget _providerTile(BuildContext context, {
    required IconData icon, required String title, required String subtitle, required String status,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(subtitle),
      trailing: Text(status, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
  );
}
