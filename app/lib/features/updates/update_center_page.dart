import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class UpdateCenterPage extends StatefulWidget {
  const UpdateCenterPage({super.key});

  @override
  State<UpdateCenterPage> createState() => _UpdateCenterPageState();
}

class _UpdateCenterPageState extends State<UpdateCenterPage> {
  static const currentVersion = '1.1.0';
  static final _releaseUri = Uri.parse('https://github.com/shinuXcode/Snote/releases/latest');
  static final _apiUri = Uri.parse('https://api.github.com/repos/shinuXcode/Snote/releases/latest');

  bool _loading = true;
  String? _latestVersion;
  String? _releaseUrl;
  String? _error;
  DateTime? _publishedAt;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(
        _apiUri,
        headers: const {'Accept': 'application/vnd.github+json'},
      );
      if (response.statusCode != 200) {
        throw Exception('Update server returned ${response.statusCode}.');
      }
      final data = jsonDecode(response.body);
      if (data is! Map) throw const FormatException('Invalid release data.');
      final tag = data['tag_name']?.toString();
      final url = data['html_url']?.toString();
      final published = data['published_at']?.toString();
      if (!mounted) return;
      setState(() {
        _latestVersion = tag?.replaceFirst(RegExp(r'^v'), '');
        _releaseUrl = url;
        _publishedAt = published == null ? null : DateTime.tryParse(published)?.toLocal();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  bool get _updateAvailable {
    final latest = _latestVersion;
    if (latest == null) return false;
    return _versionParts(latest).compareTo(_versionParts(currentVersion)) > 0;
  }

  _ComparableVersion _versionParts(String value) {
    final parts = value.split('.').map((v) => int.tryParse(v) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return _ComparableVersion(parts[0], parts[1], parts[2]);
  }

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the release link.')),
      );
    }
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
                  const Text('Installed version: 1.1.0'),
                  const SizedBox(height: 5),
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
                          ? 'A newer release is available: ' + (_latestVersion ?? '')
                          : 'You are on the latest checked release' +
                              (_latestVersion == null ? '' : ' (' + _latestVersion! + ').'),
                    ),
                  if (_publishedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Published ' +
                          _publishedAt!.day.toString().padLeft(2, '0') +
                          '/' +
                          _publishedAt!.month.toString().padLeft(2, '0') +
                          '/' +
                          _publishedAt!.year.toString(),
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
          const SizedBox(height: 14),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.new_releases_outlined),
                      SizedBox(width: 10),
                      Text('What’s new in 1.1.0', style: TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text('• Pro PDF workspace with thumbnails, text search, highlight, underline, strikeout and page editing.'),
                  Text('• Live vector ink with fountain and calligraphy tools, pressure-aware erasing and expanded pen controls.'),
                  Text('• Smart Templates and two-finger writing gestures.'),
                  Text('• Optional end-to-end encryption for note content and local attachments.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Card(
            child: ListTile(
              leading: Icon(Icons.notifications_active_outlined),
              title: Text(
                'Notification center',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                'Release checks and important app notices appear here. Snote does not silently install updates; a normal signed package update can be installed over the existing Snote app.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparableVersion implements Comparable<_ComparableVersion> {
  final int major;
  final int minor;
  final int patch;
  const _ComparableVersion(this.major, this.minor, this.patch);

  @override
  int compareTo(_ComparableVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }
}
