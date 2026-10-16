import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_version.dart';
import '../../data/local/notification_repository.dart';

class UpdateCenterPage extends StatefulWidget {
  const UpdateCenterPage({super.key});

  @override
  State<UpdateCenterPage> createState() => _UpdateCenterPageState();
}

class _UpdateCenterPageState extends State<UpdateCenterPage> {
  static const currentVersion = snoteVersionName;
  static final _releaseUri =
      Uri.parse('https://github.com/shinuXcode/Snote/releases/latest');
  static final _apiUri =
      Uri.parse('https://api.github.com/repos/shinuXcode/Snote/releases?per_page=30');

  final _notificationRepository = NotificationRepository();
  bool _loading = true;
  bool _notificationsLoading = true;
  String? _latestVersion;
  String? _releaseUrl;
  String? _error;
  DateTime? _publishedAt;
  List<AppNotification> _notifications = const [];

  @override
  void initState() {
    super.initState();
    _check();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final notifications = await _notificationRepository.list();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _notificationsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _notificationsLoading = false);
    }
  }

  Future<void> _check() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await http
          .get(
            _apiUri,
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('Update server returned ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! List) throw const FormatException('Invalid release list.');
      final betaChannel = currentVersion.contains('-beta.');
      final releases = decoded.whereType<Map>().where((release) {
        if (release['draft'] == true) return false;
        if (!betaChannel && release['prerelease'] == true) return false;
        final tag = release['tag_name']?.toString();
        return tag != null && tag.isNotEmpty;
      }).toList();
      if (releases.isEmpty) throw const FormatException('No eligible release was found.');
      releases.sort((left, right) {
        final leftTag = left['tag_name']?.toString() ?? '';
        final rightTag = right['tag_name']?.toString() ?? '';
        return _versionParts(rightTag).compareTo(_versionParts(leftTag));
      });
      final release = releases.first;
      final tag = release['tag_name']?.toString();
      final normalizedVersion = tag?.replaceFirst(RegExp(r'^v'), '');
      final url = release['html_url']?.toString();
      final published = release['published_at']?.toString();
      if (!mounted) return;
      setState(() {
        _latestVersion = normalizedVersion;
        _releaseUrl = url;
        _publishedAt =
            published == null ? null : DateTime.tryParse(published)?.toLocal();
        _loading = false;
      });

      if (normalizedVersion != null &&
          _isNewer(normalizedVersion, currentVersion)) {
        await _notificationRepository.addOnce(
          id: 'release:$normalizedVersion',
          category: 'release',
          title: 'Snote $normalizedVersion is available',
          body: 'A newer version is available from the official release page.',
          actionUrl: url ?? _releaseUri.toString(),
        );
        await _loadNotifications();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  bool _isNewer(String candidate, String installed) =>
      _versionParts(candidate).compareTo(_versionParts(installed)) > 0;

  bool get _updateAvailable {
    final latest = _latestVersion;
    return latest != null && _isNewer(latest, currentVersion);
  }

  _ComparableVersion _versionParts(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^v'), '');
    final match = RegExp(
      r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+\d+)?$',
    ).firstMatch(normalized);
    if (match == null) {
      final parts = normalized
          .split('.')
          .map((part) => int.tryParse(RegExp(r'^\d+').firstMatch(part)?.group(0) ?? '') ?? 0)
          .toList();
      while (parts.length < 3) {
        parts.add(0);
      }
      return _ComparableVersion(parts[0], parts[1], parts[2]);
    }
    final preRelease = match.group(4);
    final tokens = preRelease?.toLowerCase().split(RegExp(r'[.-]')) ?? const <String>[];
    final preReleaseName = tokens.isEmpty ? null : tokens.first;
    var preReleaseNumber = 0;
    for (final token in tokens.skip(1)) {
      final parsed = int.tryParse(token);
      if (parsed != null) {
        preReleaseNumber = parsed;
        break;
      }
    }
    return _ComparableVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      preRelease: preReleaseName,
      preReleaseNumber: preReleaseNumber,
    );
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the release link.')),
      );
    }
  }

  Future<void> _openNotification(AppNotification notification) async {
    await _notificationRepository.markRead(notification.id);
    final url = notification.actionUrl;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
        await _open(uri);
      }
    }
    await _loadNotifications();
  }

  Future<void> _dismiss(AppNotification notification) async {
    await _notificationRepository.dismiss(notification.id);
    await _loadNotifications();
  }

  Future<void> _markAllRead() async {
    await _notificationRepository.markAllRead();
    await _loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final release = _releaseUrl == null
        ? _releaseUri
        : Uri.tryParse(_releaseUrl!) ?? _releaseUri;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Updates & notifications',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _check,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Check for updates',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 36),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      CircleAvatar(child: Icon(Icons.system_update_alt_rounded)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Snote update center',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text('Installed version: $snoteVersionLabel'),
                  const SizedBox(height: 8),
                  if (_loading)
                    const LinearProgressIndicator()
                  else if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    )
                  else
                    Text(
                      _updateAvailable
                          ? 'A newer release is available: ${_latestVersion ?? ''}'
                          : 'You are on the latest checked release'
                              '${_latestVersion == null ? '' : ' ($_latestVersion).'}',
                    ),
                  if (_publishedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Published ${_publishedAt!.day.toString().padLeft(2, '0')}/'
                      '${_publishedAt!.month.toString().padLeft(2, '0')}/'
                      '${_publishedAt!.year}',
                    ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () => _open(release),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open release page'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Notification center',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: _notifications.isEmpty ? null : _markAllRead,
                child: const Text('Mark all read'),
              ),
            ],
          ),
          if (_notificationsLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_notifications.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Column(
                  children: [
                    Icon(Icons.notifications_none_rounded, size: 38),
                    SizedBox(height: 8),
                    Text('You are all caught up.'),
                    SizedBox(height: 4),
                    Text(
                      'Release updates and important app notices will appear here.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._notifications.map((notification) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: notification.isRead
                          ? Theme.of(context).colorScheme.surfaceContainerHighest
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        notification.category == 'release'
                            ? Icons.system_update_alt_rounded
                            : Icons.notifications_active_outlined,
                      ),
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: notification.isRead
                            ? FontWeight.w500
                            : FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(notification.body),
                    onTap: () => _openNotification(notification),
                    trailing: IconButton(
                      tooltip: 'Dismiss notification',
                      onPressed: () => _dismiss(notification),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}

class _ComparableVersion implements Comparable<_ComparableVersion> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;
  final int preReleaseNumber;

  const _ComparableVersion(
    this.major,
    this.minor,
    this.patch, {
    this.preRelease,
    this.preReleaseNumber = 0,
  });

  int _stageRank(String? name) {
    if (name == null) return 4;
    switch (name) {
      case 'dev':
      case 'alpha':
        return 0;
      case 'beta':
        return 1;
      case 'rc':
        return 2;
      default:
        return 1;
    }
  }

  @override
  int compareTo(_ComparableVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    final leftRank = _stageRank(preRelease);
    final rightRank = _stageRank(other.preRelease);
    if (leftRank != rightRank) return leftRank.compareTo(rightRank);
    if (preRelease == null || other.preRelease == null) return 0;
    if (preRelease != other.preRelease) {
      return preRelease!.compareTo(other.preRelease!);
    }
    return preReleaseNumber.compareTo(other.preReleaseNumber);
  }
}
