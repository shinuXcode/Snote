import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'google_drive_oauth_service.dart';
import 'google_drive_sync_transport.dart';
import 'snote_sync_runtime.dart';
import 'sync_journal.dart';
import 'sync_key_vault.dart';
import 'sync_provider_settings.dart';

class SyncCenterPage extends StatefulWidget {
  const SyncCenterPage({super.key});

  @override
  State<SyncCenterPage> createState() => _SyncCenterPageState();
}

class _SyncCenterPageState extends State<SyncCenterPage> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _vault = SyncKeyVault();
  final _providerSettings = SyncProviderSettings();
  final _googleOAuth = GoogleDriveOAuthService.instance;

  SyncJournalStatus? _status;
  GoogleDriveAccount? _googleAccount;
  String? _googleSetupError;
  bool _googleLoading = false;
  bool _loading = true;
  bool _running = false;
  bool _paired = false;
  String? _lastResult;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final values = await Future.wait<Object?>([
        SyncJournal.status(),
        _vault.readActiveKey(),
        _providerSettings.readWebDav(),
      ]);
      if (!mounted) return;
      final credentials = values[2] as WebDavCredentials?;
      GoogleDriveAccount? googleAccount;
      String? googleSetupError;
      if (_googleOAuth.isPlatformSupported) {
        try {
          googleAccount = await _googleOAuth.restoreAccount();
        } catch (error) {
          googleSetupError = error.toString();
        }
      } else {
        googleSetupError =
            'Google Drive sign-in is currently supported on Android, iOS and macOS only.';
      }
      if (!mounted) return;
      setState(() {
        _googleAccount = googleAccount;
        _googleSetupError = googleSetupError;
        _status = values[0] as SyncJournalStatus;
        _paired = values[1] != null;
        if (credentials != null) {
          _url.text = credentials.collectionUrl;
          _username.text = credentials.username;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = error; _loading = false; });
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showRecoveryKey() async {
    try {
      final creation = await _vault.createIfMissing();
      final key = creation.recoveryKey ?? await _vault.exportRecoveryKey();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(creation.created ? 'Pair another device' : 'Device recovery key'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter this key on the trusted device you want to pair. Anyone with this key can read and write your synced notes. Keep it private.'),
              const SizedBox(height: 12),
              SelectableText(key, style: const TextStyle(fontFamily: 'monospace')),
            ],
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: key));
                if (context.mounted) Navigator.pop(context);
                _message('Recovery key copied. Share it only with your trusted device.');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy key'),
            ),
          ],
        ),
      );
      await _load();
    } catch (error) {
      _message('Could not prepare recovery key: $error');
    }
  }

  Future<void> _importRecoveryKey() async {
    final controller = TextEditingController();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Pair this device'),
          content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Recovery key',
              hintText: 'Paste the key from your trusted device',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import securely')),
          ],
        ),
      );
      if (accepted != true) return;
      await _vault.importRecoveryKey(controller.text);
      await _load();
      _message('This device is paired. Configure the same sync provider to restore notes.');
    } catch (error) {
      _message('Pairing failed: $error');
    } finally {
      controller.dispose();
    }
  }

  Future<void> _connectGoogleDrive() async {
    if (_googleLoading || _running) return;
    setState(() { _googleLoading = true; _googleSetupError = null; });
    try {
      final account = await _googleOAuth.signInAndAuthorize();
      if (!mounted) return;
      setState(() => _googleAccount = account);
      _message('Google Drive connected for ${account.email}.');
    } catch (error) {
      if (mounted) setState(() => _googleSetupError = error.toString());
      _message('Google Drive connection failed: $error');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _disconnectGoogleDrive() async {
    try {
      await _googleOAuth.disconnect();
      if (!mounted) return;
      setState(() => _googleAccount = null);
      _message('Google Drive disconnected and authorization revoked.');
    } catch (error) {
      _message('Could not disconnect Google Drive: $error');
    }
  }

  Future<void> _runGoogleDriveSync() async {
    if (_running || _loading) return;
    setState(() { _running = true; _error = null; _lastResult = null; });
    try {
      final key = await _vault.readActiveKey();
      if (key == null) {
        throw StateError('Pair this device with your recovery key before syncing.');
      }
      // This runs from the Sync button, so Google may display consent if needed.
      final account = await _googleOAuth.signInAndAuthorize();
      if (mounted) setState(() => _googleAccount = account);
      final transport = GoogleDriveSyncTransport(
        accessTokenProvider: _googleOAuth.accessToken,
      );
      final result = await SnoteSyncRuntime(
        transport: transport,
        sharedKey: key.keyBytes,
      ).synchronize();
      if (!mounted) return;
      setState(() {
        _lastResult = 'Google Drive: uploaded ${result.uploadedOperations} changes; '
            'applied ${result.appliedPacks} remote packs; skipped ${result.skippedPacks}.';
      });
      await _load();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _googleSetupError = error.toString();
        });
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _saveWebDav() async {
    try {
      await _providerSettings.saveWebDav(
        collectionUrl: _url.text,
        username: _username.text,
        password: _password.text,
      );
      _password.clear();
      _message('WebDAV credentials saved in secure storage.');
    } catch (error) {
      _message('Could not save WebDAV settings: $error');
    }
  }

  Future<void> _runSync() async {
    if (_running) return;
    setState(() { _running = true; _error = null; _lastResult = null; });
    try {
      final credentials = await _providerSettings.readWebDav();
      if (credentials == null) {
        throw StateError('Configure and save your HTTPS WebDAV details first.');
      }
      final key = await _vault.readActiveKey();
      if (key == null) {
        throw StateError('Pair this device with a recovery key before syncing.');
      }
      final result = await SnoteSyncRuntime(
        transport: credentials.createTransport(),
        sharedKey: key.keyBytes,
      ).synchronize();
      if (!mounted) return;
      setState(() {
        _lastResult = 'Uploaded ${result.uploadedOperations} changes; applied ${result.appliedPacks} remote packs; skipped ${result.skippedPacks}.';
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync & Devices'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _loading || _running ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.devices_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Local-first synchronization', style: TextStyle(fontWeight: FontWeight.w800))),
                  Chip(label: Text(_paired ? 'Paired' : 'Not paired')),
                ]),
                const SizedBox(height: 8),
                const Text('Your notes remain local until you configure a provider and explicitly start sync. Remote change packs are encrypted before upload.'),
                const SizedBox(height: 12),
                if (_loading) const LinearProgressIndicator()
                else if (_error != null) Text('Sync error: $_error', style: TextStyle(color: colors.error))
                else const Row(children: [
                  Icon(Icons.check_circle_outline, size: 19),
                  SizedBox(width: 8),
                  Text('Local change journal available'),
                ]),
                if (_lastResult != null) ...[
                  const SizedBox(height: 10),
                  Text(_lastResult!, style: TextStyle(color: colors.primary)),
                ],
              ]),
            )),
            const SizedBox(height: 12),
            _heading(context, 'Pair your devices'),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Use the same recovery key on every device. The key is stored in Android secure storage and is never uploaded to your provider.'),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: _running ? null : _showRecoveryKey,
                    icon: const Icon(Icons.key_rounded),
                    label: Text(_paired ? 'Show recovery key' : 'Create pairing key'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _running || _paired ? null : _importRecoveryKey,
                    icon: const Icon(Icons.input_rounded),
                    label: const Text('Import key'),
                  ),
                ]),
              ]),
            )),
            const SizedBox(height: 12),
            _heading(context, 'Google Drive encrypted sync'),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Snotee stores encrypted sync packs in Google Drive appDataFolder. '
                    'It does not request access to your normal Drive files.',
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(
                      _googleAccount == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                      color: _googleAccount == null ? colors.outline : colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _googleAccount?.email ?? 'Google Drive not connected',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                  if (_googleSetupError != null) ...[
                    const SizedBox(height: 8),
                    Text(_googleSetupError!, style: TextStyle(color: colors.error)),
                  ],
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: !_googleOAuth.isPlatformSupported || _googleLoading || _running ? null : _connectGoogleDrive,
                      icon: _googleLoading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login_rounded),
                      label: Text(_googleAccount == null ? 'Connect Google' : 'Reconnect Google'),
                    ),
                    if (_googleAccount != null)
                      TextButton.icon(
                        onPressed: _googleLoading || _running ? null : _disconnectGoogleDrive,
                        icon: const Icon(Icons.link_off_rounded),
                        label: const Text('Disconnect'),
                      ),
                    FilledButton.icon(
                      onPressed: !_googleOAuth.isPlatformSupported || _running || _loading || _googleLoading ? null : _runGoogleDriveSync,
                      icon: _running
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sync_rounded),
                      label: const Text('Sync with Drive'),
                    ),
                  ]),
                ],
              ),
            )),
            const SizedBox(height: 12),
            _heading(context, 'WebDAV encrypted storage'),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'HTTPS collection URL',
                    hintText: 'https://cloud.example.com/remote.php/dav/files/user/snotee/',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _username,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Password / app password', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _running ? null : _saveWebDav,
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Save securely'),
                  ),
                ),
              ]),
            )),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _running || _loading ? null : _runSync,
              icon: _running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_rounded),
              label: Text(_running ? 'Synchronizing…' : 'Sync now'),
            ),
            const SizedBox(height: 12),
            _heading(context, 'This device'),
            Card(child: Column(children: [
              ListTile(
                leading: const Icon(Icons.fingerprint_rounded),
                title: const Text('Device identity'),
                subtitle: Text(_status?.deviceId ?? 'Preparing…', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Copy device ID',
                  onPressed: _status == null ? null : () async {
                    await Clipboard.setData(ClipboardData(text: _status!.deviceId));
                    _message('Device ID copied');
                  },
                  icon: const Icon(Icons.copy_rounded),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.pending_actions_rounded),
                title: const Text('Pending local changes'),
                trailing: Text((_status?.pendingOperations ?? 0).toString()),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.numbers_rounded),
                title: const Text('Local change sequence'),
                trailing: Text((_status?.lastSequence ?? 0).toString()),
              ),
            ])),
            const SizedBox(height: 12),
            Card(color: colors.surfaceContainerLow, child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('WebDAV sync now uses encrypted immutable change packs and transactional local application. Google Drive OAuth, background scheduling, conflict-resolution controls, and real-device two-way acceptance testing still require completion before cross-device sync can be declared production-ready.'),
            )),
          ],
        ),
      ),
    );
  }

  Widget _heading(BuildContext context, String value) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
  );
}
