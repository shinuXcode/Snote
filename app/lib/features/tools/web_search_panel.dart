import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/settings/app_settings.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Embedded browser for search and reference lookup while keeping the user in Snote.
/// Known ad/tracker domains are blocked at navigation level. WebView does not expose
/// a universal subresource request filter, so this is best-effort protection.
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
  final Set<String> _blockedHosts = <String>{
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'adservice.google.com', 'googletagmanager.com', 'google-analytics.com',
    'connect.facebook.net', 'facebook.com/tr', 'scorecardresearch.com',
    'ads.yahoo.com', 'adnxs.com', 'taboola.com', 'outbrain.com',
    'hotjar.com', 'clarity.ms',
  };
  late final WebViewController _controller;
  final List<String> _recentQueries = <String>[];
  bool _loading = false;
  double? _windowWidth;
  double? _windowHeight;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;
  int _blockedCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          unawaited(SnoteSettings.instance.setString('webSearchLastUrl', url));
          if (mounted) setState(() { _loading = true; _error = null; });
        },
        onPageFinished: (_) => _refreshNavigationState(),
        onWebResourceError: (error) {
          if (error.isForMainFrame == true && mounted) {
            setState(() => _error = 'Page could not be loaded: ${error.description}');
          }
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
            return NavigationDecision.prevent;
          }
          final host = uri.host.toLowerCase();
          final blocked = _blockedHosts.any((domain) =>
              host == domain || host.endsWith('.$domain') || uri.host.contains(domain));
          if (blocked) {
            _blockedCount++;
            if (mounted) setState(() {});
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadRequest(_restoreUri());
  }

  Uri _restoreUri() {
    final saved = SnoteSettings.instance.getString('webSearchLastUrl').trim();
    final uri = Uri.tryParse(saved);
    if (uri != null && const {'http', 'https'}.contains(uri.scheme)) return uri;
    return Uri.https('www.google.com', '/');
  }

  Future<void> _refreshNavigationState() async {
    final back = await _controller.canGoBack();
    final forward = await _controller.canGoForward();
    if (mounted) {
      setState(() {
        _loading = false;
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  Future<void> _search([String? supplied]) async {
    final query = (supplied ?? _query.text).trim();
    if (query.isEmpty) return;
    _query.text = query;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _recentQueries.remove(query);
      _recentQueries.insert(0, query);
      if (_recentQueries.length > 8) _recentQueries.removeLast();
    });
    final parsed = Uri.tryParse(query);
    final explicitWebUrl = parsed != null &&
        const {'http', 'https'}.contains(parsed.scheme) &&
        parsed.host.isNotEmpty;
    final domainLike = !query.contains(RegExp(r'\\s')) &&
        query.contains('.') &&
        !query.startsWith('.');
    final direct = explicitWebUrl
        ? parsed
        : domainLike
            ? Uri.tryParse('https://$query')
            : null;
    if (direct != null && const {'http', 'https'}.contains(direct.scheme) && direct.host.isNotEmpty) {
      await _controller.loadRequest(direct);
    } else {
      await _controller.loadRequest(Uri.https(
        'www.google.com',
        '/search',
        <String, String>{'q': query, 'igu': '1'},
      ));
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final maxWidth = math.max(250.0, media.width - 28);
    final maxHeight = math.max(300.0, media.height - 48);
    final storedWidth = SnoteSettings.instance.getDouble('webSearchWindowWidth');
    final storedHeight = SnoteSettings.instance.getDouble('webSearchWindowHeight');
    final width = (_windowWidth ?? (storedWidth >= 250 ? storedWidth : math.min(900.0, maxWidth))).clamp(250.0, maxWidth).toDouble();
    final height = (_windowHeight ?? (storedHeight >= 300 ? storedHeight : math.min(720.0, maxHeight))).clamp(300.0, maxHeight).toDouble();
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
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
              child: Row(children: <Widget>[
                IconButton(
                  tooltip: 'Back',
                  onPressed: _canGoBack ? () async { await _controller.goBack(); } : null,
                  icon: const Icon(Icons.arrow_back),
                ),
                IconButton(
                  tooltip: 'Forward',
                  onPressed: _canGoForward ? () async { await _controller.goForward(); } : null,
                  icon: const Icon(Icons.arrow_forward),
                ),
                IconButton(
                  tooltip: 'Reload',
                  onPressed: () async { await _controller.reload(); },
                  icon: const Icon(Icons.refresh),
                ),
                const Expanded(child: Text('Snote Browser', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton(
                  tooltip: 'Close browser',
                  onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Enter a URL or search the web',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Search',
                    onPressed: () => _search(),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(_error!, style: TextStyle(color: colors.error)),
              ),
            Expanded(child: WebViewWidget(controller: _controller)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(children: <Widget>[
                Icon(Icons.shield_outlined, size: 16, color: colors.secondary),
                const SizedBox(width: 6),
                Expanded(child: Text('Best-effort tracker navigation blocking · $_blockedCount blocked', style: Theme.of(context).textTheme.labelSmall)),
                if (_recentQueries.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Recent searches',
                    icon: const Icon(Icons.history, size: 20),
                    onSelected: _search,
                    itemBuilder: (_) => _recentQueries.map((q) => PopupMenuItem<String>(value: q, child: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis))).toList(),
                  ),
              ]),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (details) => setState(() {
                  _windowWidth = (width + details.delta.dx).clamp(250.0, maxWidth).toDouble();
                  _windowHeight = (height + details.delta.dy).clamp(300.0, maxHeight).toDouble();
                }),
                onPanEnd: (_) {
                  unawaited(SnoteSettings.instance.setDouble('webSearchWindowWidth', _windowWidth ?? width));
                  unawaited(SnoteSettings.instance.setDouble('webSearchWindowHeight', _windowHeight ?? height));
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 10, 6),
                  child: Icon(Icons.open_in_full_rounded, size: 17, color: colors.secondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
