import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Lightweight Google search launcher. Search opens in the platform's
/// in-app browser when supported, with a safe external-browser fallback.
class SnoteWebSearchPanel extends StatefulWidget {
  const SnoteWebSearchPanel({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        useRootNavigator: true,
        builder: (_) => const SnoteWebSearchPanel(),
      );

  @override
  State<SnoteWebSearchPanel> createState() => _SnoteWebSearchPanelState();
}

class _SnoteWebSearchPanelState extends State<SnoteWebSearchPanel> {
  final TextEditingController _query = TextEditingController();
  final List<String> _recentQueries = <String>[];
  bool _opening = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search([String? supplied]) async {
    final query = (supplied ?? _query.text).trim();
    if (query.isEmpty || _opening) return;
    _query.text = query;
    FocusScope.of(context).unfocus();
    setState(() {
      _opening = true;
      _error = null;
      _recentQueries.remove(query);
      _recentQueries.insert(0, query);
      if (_recentQueries.length > 8) _recentQueries.removeLast();
    });

    final uri = Uri.https('www.google.com', '/search', <String, String>{
      'q': query,
      'igu': '1',
    });
    try {
      var opened = false;
      try {
        opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      } catch (_) {
        // Some desktop launchers do not implement an in-app browser.
      }
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!opened && mounted) {
        setState(() => _error = 'Could not open Google Search. Check your browser and try again.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Google Search could not be opened: $error');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = math.min(620.0, math.max(250.0, media.width - 28));
    final height = math.min(480.0, math.max(250.0, media.height - 48));
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.travel_explore_rounded, color: colors.primary),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Google Search',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close search',
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _query,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Search Google…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search Google',
                    onPressed: _opening ? null : _search,
                    icon: _opening
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Recent searches', style: Theme.of(context).textTheme.titleSmall),
            ),
            Expanded(
              child: _recentQueries.isEmpty
                  ? Center(
                      child: Text(
                        'Enter a search above. Results open in the in-app browser.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _recentQueries.length,
                      itemBuilder: (context, index) {
                        final query = _recentQueries[index];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.history_rounded),
                          title: Text(query, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: const Icon(Icons.north_west_rounded, size: 17),
                          onTap: () => _search(query),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
