import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// In-app search surface. Results are shown in Snote and opened externally
/// only when the user selects one.
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
  bool _loading = false;
  String? _error;
  List<_WebResult> _results = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String _plainText(String value) => value
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\\s+'), ' ')
      .trim();

  Uri? _resultUri(String value) {
    var raw = value.replaceAll('&amp;', '&');
    if (raw.startsWith('//')) raw = 'https:$raw';
    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    final redirect = parsed.queryParameters['uddg'];
    if (redirect != null && redirect.isNotEmpty) {
      return Uri.tryParse(redirect);
    }
    if (parsed.scheme == 'https' || parsed.scheme == 'http') return parsed;
    return null;
  }

  Future<void> _search([String? supplied]) async {
    final query = (supplied ?? _query.text).trim();
    if (query.isEmpty || _loading) return;
    _query.text = query;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _results = const [];
    });
    try {
      final uri = Uri.https('html.duckduckgo.com', '/html/', {
        'q': query,
        'kl': 'us-en',
      });
      final response = await http
          .get(uri, headers: const {'User-Agent': 'Mozilla/5.0 Snote/1.1'})
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Search service returned HTTP ${response.statusCode}.');
      }

      final html = response.body;
      final anchors = RegExp(
        r'<a\\b(?=[^>]*class="[^"]*result__a)[^>]*>.*?</a>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html);
      final snippets = RegExp(
        r'<(?:a|div)[^>]*class="[^"]*result__snippet[^"]*"[^>]*>.*?</(?:a|div)>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(html).map((match) => _plainText(match.group(0) ?? '')).toList();
      final results = <_WebResult>[];
      for (final match in anchors) {
        final anchor = match.group(0) ?? '';
        final href = RegExp(r'href="([^"]+)"', caseSensitive: false)
            .firstMatch(anchor)
            ?.group(1);
        final title = _plainText(anchor);
        final url = href == null ? null : _resultUri(href);
        if (title.isEmpty || url == null || url.host.contains('duckduckgo.com')) {
          continue;
        }
        if (results.any((item) => item.url == url)) continue;
        final snippet = results.length < snippets.length ? snippets[results.length] : '';
        results.add(_WebResult(title: title, url: url, snippet: snippet));
        if (results.length >= 20) break;
      }
      if (!mounted) return;
      setState(() {
        _results = results;
        if (results.isEmpty) {
          _error = 'No readable results were returned. Try another query.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Search failed: ${error.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _openGoogleSearch() async {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    final uri = Uri.https('www.google.com', '/search', {'q': query});
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Search.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Search could not be opened: $error')),
        );
      }
    }
  }

  Future<void> _openResult(Uri uri) async {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this search result.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open result: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = math.min(760.0, math.max(240.0, media.width - 28));
    final height = math.min(680.0, math.max(280.0, media.height - 48));
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.travel_explore_rounded),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Web search', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'Close web search',
                    onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Search the web…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: _loading ? null : _search,
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _openGoogleSearch,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open in Google Search'),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off_rounded, size: 34),
                                const SizedBox(height: 8),
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _search,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final result = _results[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                              leading: const CircleAvatar(
                                radius: 17,
                                child: Icon(Icons.public_rounded, size: 18),
                              ),
                              title: Text(
                                result.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(result.url.host, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    if (result.snippet.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(result.snippet, maxLines: 3, overflow: TextOverflow.ellipsis),
                                      ),
                                  ],
                                ),
                              ),
                              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                              onTap: () => _openResult(result.url),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                'Search results load online; selected pages open in your browser.',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebResult {
  final String title;
  final Uri url;
  final String snippet;

  const _WebResult({required this.title, required this.url, required this.snippet});
}
