import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/settings/app_settings.dart';

/// Embedded browser with request-level ad/tracker host blocking on Android.
class SnoteWebSearchPanel extends StatefulWidget {
  const SnoteWebSearchPanel({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
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
    'googletagservices.com', 'pagead2.googlesyndication.com',
    'adnxs.com', 'adsrvr.org', 'advertising.com', 'adform.net',
    'adroll.com', 'criteo.com', 'criteo.net', 'taboola.com', 'outbrain.com',
    'pubmatic.com', 'openx.net', 'rubiconproject.com', 'indexww.com',
    'casalemedia.com', 'lijit.com', 'sharethrough.com', 'yieldmo.com',
    'media.net', 'smartadserver.com', 'adcolony.com', 'applovin.com',
    'unityads.unity3d.com', 'moloco.com', 'inmobi.com', 'ironsrc.com',
    'hotjar.com', 'clarity.ms', 'scorecardresearch.com', 'quantserve.com',
    'connect.facebook.net', 'ads.yahoo.com', 'amazon-adsystem.com',
    's.amazon-adsystem.com', 'bidswitch.net', 'bidease.com',
    'tracking.unity3d.com', 'branch.io',
  };
  InAppWebViewController? _controller;
  final List<String> _history = <String>[];
  final List<String> _recentQueries = <String>[];
  bool _loading = false;
  bool _collapsed = false;
  double? _windowWidth;
  double? _windowHeight;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _error;
  int _blockedCount = 0;

  @override
  void initState() {
    super.initState();
    _collapsed = SnoteSettings.instance.getBool('webSearchCollapsed');
    _loadHistory();
  }

  void _loadHistory() {
    try {
      final decoded = jsonDecode(SnoteSettings.instance.getString('webSearchSessionHistory'));
      if (decoded is List) {
        for (final item in decoded) {
          if (item is String && _isHttpUrl(item) && !_history.contains(item)) {
            _history.add(item);
          }
        }
      }
    } catch (_) {
      // Invalid or old session data is safely ignored.
    }
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && const {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty;
  }

  bool _isBlockedHost(String host) {
    final normalized = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    return _blockedHosts.any((domain) =>
        normalized == domain || normalized.endsWith('.$domain'));
  }

  void _recordPage(String? value) {
    if (value == null || !_isHttpUrl(value)) return;
    unawaited(SnoteSettings.instance.setString('webSearchLastUrl', value));
    _history.remove(value);
    _history.insert(0, value);
    if (_history.length > 30) _history.removeRange(30, _history.length);
    unawaited(SnoteSettings.instance.setString('webSearchSessionHistory', jsonEncode(_history)));
    if (mounted) setState(() {});
  }

  Uri _restoreUri() {
    final saved = SnoteSettings.instance.getString('webSearchLastUrl').trim();
    final uri = Uri.tryParse(saved);
    if (uri != null && const {'http', 'https'}.contains(uri.scheme)) return uri;
    return Uri.https('www.google.com', '/');
  }

  Future<void> _refreshNavigationState() async {
    final controller = _controller;
    if (controller == null) return;
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
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
        const {'http', 'https'}.contains(parsed.scheme) && parsed.host.isNotEmpty;
    final domainLike = !query.contains(RegExp(r'\s')) && query.contains('.') && !query.startsWith('.');
    final direct = explicitWebUrl ? parsed : domainLike ? Uri.tryParse('https://$query') : null;
    final destination = direct != null && const {'http', 'https'}.contains(direct.scheme) && direct.host.isNotEmpty
        ? direct
        : Uri.https('www.google.com', '/search', <String, String>{'q': query, 'igu': '1'});
    if (_isBlockedHost(destination.host)) {
      setState(() => _error = 'This ad/tracker host is blocked by Snote.');
      return;
    }
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(destination)));
  }

  Future<void> _setCollapsed(bool value) async {
    setState(() => _collapsed = value);
    await SnoteSettings.instance.setBool('webSearchCollapsed', value);
  }

  Future<void> _openHistory(String url) async {
    await _setCollapsed(false);
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
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

    if (_collapsed) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 0),
          child: Material(
            elevation: 8,
            color: colors.primaryContainer,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: InkWell(
              onTap: () => _setCollapsed(false),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: const SizedBox(
                width: 44,
                height: 118,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.open_in_browser_rounded),
                    SizedBox(height: 8),
                    RotatedBox(quarterTurns: 1, child: Text('Browser')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

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
                IconButton(tooltip: 'Back', onPressed: _canGoBack ? () async { await _controller?.goBack(); } : null, icon: const Icon(Icons.arrow_back)),
                IconButton(tooltip: 'Forward', onPressed: _canGoForward ? () async { await _controller?.goForward(); } : null, icon: const Icon(Icons.arrow_forward)),
                IconButton(tooltip: 'Reload', onPressed: () async { await _controller?.reload(); }, icon: const Icon(Icons.refresh)),
                const Expanded(child: Text('Snote Browser · Ad blocking', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                PopupMenuButton<String>(
                  tooltip: 'Browsing session',
                  icon: const Icon(Icons.history),
                  onSelected: (value) {
                    if (value == '__collapse__') {
                      unawaited(_setCollapsed(true));
                    } else if (value == '__clear__') {
                      setState(() => _history.clear());
                      unawaited(SnoteSettings.instance.setString('webSearchSessionHistory', '[]'));
                    } else {
                      unawaited(_openHistory(value));
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(value: '__collapse__', child: Text('Collapse to screen edge')),
                    const PopupMenuItem<String>(value: '__clear__', child: Text('Clear browsing history')),
                    const PopupMenuDivider(),
                    ..._history.take(12).map((url) => PopupMenuItem<String>(
                      value: url,
                      child: SizedBox(width: 260, child: Text(Uri.tryParse(url)?.host ?? url, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    )),
                  ],
                ),
                IconButton(tooltip: 'Collapse to screen edge', onPressed: () => _setCollapsed(true), icon: const Icon(Icons.chevron_right_rounded)),
                IconButton(tooltip: 'Close browser', onPressed: () => Navigator.of(context, rootNavigator: true).pop(), icon: const Icon(Icons.close)),
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
                  suffixIcon: IconButton(tooltip: 'Go', onPressed: () => _search(), icon: const Icon(Icons.arrow_forward)),
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
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri.uri(_restoreUri())),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldInterceptRequest: true,
                  transparentBackground: false,
                  supportZoom: true,
                ),
                onWebViewCreated: (controller) => _controller = controller,
                onLoadStart: (controller, url) {
                  _recordPage(url?.toString());
                  if (mounted) setState(() { _loading = true; _error = null; });
                },
                onLoadStop: (controller, url) {
                  _recordPage(url?.toString());
                  unawaited(_refreshNavigationState());
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true && mounted) {
                    setState(() => _error = 'Page could not be loaded: ${error.description}');
                  }
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final uri = action.request.url;
                  if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  if (_isBlockedHost(uri.host)) {
                    _blockedCount++;
                    if (mounted) setState(() {});
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                shouldInterceptRequest: (controller, request) async {
                  final uri = request.url;
                  if (uri != null && _isBlockedHost(uri.host)) {
                    _blockedCount++;
                    if (mounted) setState(() {});
                    return WebResourceResponse(
                      contentType: 'text/plain',
                      data: Uint8List(0),
                      statusCode: 204,
                      reasonPhrase: 'Blocked by Snote',
                    );
                  }
                  return null;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(children: <Widget>[
                Icon(Icons.shield_outlined, size: 16, color: colors.secondary),
                const SizedBox(width: 6),
                Expanded(child: Text('Network ad/tracker domains blocked: $_blockedCount', style: Theme.of(context).textTheme.labelSmall)),
                if (_recentQueries.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Recent searches',
                    icon: const Icon(Icons.manage_search, size: 20),
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
), '');
    return _blockedHosts.any((domain) =>
        normalized == domain || normalized.endsWith('.$domain'));
  }

  void _recordPage(String? value) {
    if (value == null || !_isHttpUrl(value)) return;
    unawaited(SnoteSettings.instance.setString('webSearchLastUrl', value));
    _history.remove(value);
    _history.insert(0, value);
    if (_history.length > 30) _history.removeRange(30, _history.length);
    unawaited(SnoteSettings.instance.setString('webSearchSessionHistory', jsonEncode(_history)));
    if (mounted) setState(() {});
  }

  Uri _restoreUri() {
    final saved = SnoteSettings.instance.getString('webSearchLastUrl').trim();
    final uri = Uri.tryParse(saved);
    if (uri != null && const {'http', 'https'}.contains(uri.scheme)) return uri;
    return Uri.https('www.google.com', '/');
  }

  Future<void> _refreshNavigationState() async {
    final controller = _controller;
    if (controller == null) return;
    final back = await controller.canGoBack();
    final forward = await controller.canGoForward();
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
        const {'http', 'https'}.contains(parsed.scheme) && parsed.host.isNotEmpty;
    final domainLike = !query.contains(RegExp(r'\s')) && query.contains('.') && !query.startsWith('.');
    final direct = explicitWebUrl ? parsed : domainLike ? Uri.tryParse('https://$query') : null;
    final destination = direct != null && const {'http', 'https'}.contains(direct.scheme) && direct.host.isNotEmpty
        ? direct
        : Uri.https('www.google.com', '/search', <String, String>{'q': query, 'igu': '1'});
    if (_isBlockedHost(destination.host)) {
      setState(() => _error = 'This ad/tracker host is blocked by Snote.');
      return;
    }
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(destination)));
  }

  Future<void> _setCollapsed(bool value) async {
    setState(() => _collapsed = value);
    await SnoteSettings.instance.setBool('webSearchCollapsed', value);
  }

  Future<void> _openHistory(String url) async {
    await _setCollapsed(false);
    await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
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

    if (_collapsed) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 0),
          child: Material(
            elevation: 8,
            color: colors.primaryContainer,
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
            child: InkWell(
              onTap: () => _setCollapsed(false),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: const SizedBox(
                width: 44,
                height: 118,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.open_in_browser_rounded),
                    SizedBox(height: 8),
                    RotatedBox(quarterTurns: 1, child: Text('Browser')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

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
                IconButton(tooltip: 'Back', onPressed: _canGoBack ? () async { await _controller?.goBack(); } : null, icon: const Icon(Icons.arrow_back)),
                IconButton(tooltip: 'Forward', onPressed: _canGoForward ? () async { await _controller?.goForward(); } : null, icon: const Icon(Icons.arrow_forward)),
                IconButton(tooltip: 'Reload', onPressed: () async { await _controller?.reload(); }, icon: const Icon(Icons.refresh)),
                const Expanded(child: Text('Snote Browser · Ad blocking', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
                PopupMenuButton<String>(
                  tooltip: 'Browsing session',
                  icon: const Icon(Icons.history),
                  onSelected: (value) {
                    if (value == '__collapse__') {
                      unawaited(_setCollapsed(true));
                    } else if (value == '__clear__') {
                      setState(() => _history.clear());
                      unawaited(SnoteSettings.instance.setString('webSearchSessionHistory', '[]'));
                    } else {
                      unawaited(_openHistory(value));
                    }
                  },
                  itemBuilder: (_) => <PopupMenuEntry<String>>[
                    const PopupMenuItem<String>(value: '__collapse__', child: Text('Collapse to screen edge')),
                    const PopupMenuItem<String>(value: '__clear__', child: Text('Clear browsing history')),
                    const PopupMenuDivider(),
                    ..._history.take(12).map((url) => PopupMenuItem<String>(
                      value: url,
                      child: SizedBox(width: 260, child: Text(Uri.tryParse(url)?.host ?? url, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    )),
                  ],
                ),
                IconButton(tooltip: 'Collapse to screen edge', onPressed: () => _setCollapsed(true), icon: const Icon(Icons.chevron_right_rounded)),
                IconButton(tooltip: 'Close browser', onPressed: () => Navigator.of(context, rootNavigator: true).pop(), icon: const Icon(Icons.close)),
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
                  suffixIcon: IconButton(tooltip: 'Go', onPressed: () => _search(), icon: const Icon(Icons.arrow_forward)),
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
            Expanded(
              child: InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri.uri(_restoreUri())),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  useShouldInterceptRequest: true,
                  transparentBackground: false,
                  supportZoom: true,
                ),
                onWebViewCreated: (controller) => _controller = controller,
                onLoadStart: (controller, url) {
                  _recordPage(url?.toString());
                  if (mounted) setState(() { _loading = true; _error = null; });
                },
                onLoadStop: (controller, url) {
                  _recordPage(url?.toString());
                  unawaited(_refreshNavigationState());
                },
                onReceivedError: (controller, request, error) {
                  if (request.isForMainFrame == true && mounted) {
                    setState(() => _error = 'Page could not be loaded: ${error.description}');
                  }
                },
                shouldOverrideUrlLoading: (controller, action) async {
                  final uri = action.request.url;
                  if (uri == null || !const {'http', 'https'}.contains(uri.scheme)) {
                    return NavigationActionPolicy.CANCEL;
                  }
                  if (_isBlockedHost(uri.host)) {
                    _blockedCount++;
                    if (mounted) setState(() {});
                    return NavigationActionPolicy.CANCEL;
                  }
                  return NavigationActionPolicy.ALLOW;
                },
                shouldInterceptRequest: (controller, request) async {
                  final uri = request.url;
                  if (uri != null && _isBlockedHost(uri.host)) {
                    _blockedCount++;
                    if (mounted) setState(() {});
                    return WebResourceResponse(
                      contentType: 'text/plain',
                      data: Uint8List(0),
                      statusCode: 204,
                      reasonPhrase: 'Blocked by Snote',
                    );
                  }
                  return null;
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(children: <Widget>[
                Icon(Icons.shield_outlined, size: 16, color: colors.secondary),
                const SizedBox(width: 6),
                Expanded(child: Text('Network ad/tracker domains blocked: $_blockedCount', style: Theme.of(context).textTheme.labelSmall)),
                if (_recentQueries.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Recent searches',
                    icon: const Icon(Icons.manage_search, size: 20),
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
