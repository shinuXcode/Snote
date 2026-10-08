import 'dart:typed_data';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/models/stroke.dart';
import '../../canvas_engine/models/stroke_codec.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';
import '../../canvas_engine/widgets/snote_canvas_controller.dart';
import '../../data/local/file_document_repository.dart';
import '../../data/local/note_repository.dart';
import 'pdf_workspace_service.dart';

enum _Markup { none, highlight, underline, strikeout }

class PdfProWorkspacePage extends StatefulWidget {
  final String? folderId;
  const PdfProWorkspacePage({super.key, this.folderId});
  @override State<PdfProWorkspacePage> createState() => _PdfProWorkspacePageState();
}

class _PdfProWorkspacePageState extends State<PdfProWorkspacePage> {
  final _files = FileDocumentRepository();
  final _notes = NoteRepository();
  final _pdf = const PdfWorkspaceService();
  final _search = TextEditingController();
  final _inkController = SnoteCanvasController();

  PdfViewerController? _viewer;
  pdfx.PdfDocument? _thumbDoc;
  Uint8List? _bytes;
  DocumentAsset? _asset;
  List<Uint8List?> _thumbs = <Uint8List?>[];
  final Map<int, Map<String, Object?>> _ink = <int, Map<String, Object?>>{};
  final Map<int, Size> _inkSizes = <int, Size>{};

  int _page = 1;
  int _pageCount = 0;
  int _revision = 0;
  bool _loading = false;
  bool _inkMode = false;
  bool _showThumbs = true;
  _Markup _markup = _Markup.none;
  CanvasTool _inkTool = CanvasTool.ballpoint;
  Color _inkColor = const Color(0xff263238);
  double _inkSize = 3;

  Map<String, Object?> _inkDocument(int page) =>
      _ink[page] ??= <String, Object?>{'version': 4, 'strokes': <Object?>[]};

  Future<void> _importPdf() async {
    if (_loading) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
    );
    if (file == null) return;
    setState(() => _loading = true);
    try {
      final bytes = await file.readAsBytes();
      final note = await _notes.create(
        title: file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ''),
        folderId: widget.folderId,
      );
      final asset = await _files.saveBytes(
        noteId: note.id,
        name: file.name,
        type: 'pdf',
        bytes: bytes,
        metadata: <String, dynamic>{'source': 'pdf-import', 'isCover': true},
      );
      await _install(bytes, asset);
    } catch (e) {
      if (mounted) _snack('PDF import failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _install(Uint8List bytes, DocumentAsset asset) async {
    _viewer?.dispose();
    _viewer = PdfViewerController();
    await _thumbDoc?.close();
    _thumbDoc = null;
    _thumbs = <Uint8List?>[];
    _ink.clear();
    _inkSizes.clear();
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _asset = asset;
      _page = 1;
      _pageCount = 0;
      _revision++;
      _markup = _Markup.none;
      _inkMode = false;
    });
    _loadThumbs(bytes);
  }

  Future<void> _loadThumbs(Uint8List bytes) async {
    try {
      final doc = await pdfx.PdfDocument.openData(bytes);
      if (!mounted) {
        await doc.close();
        return;
      }
      _thumbDoc = doc;
      setState(() => _thumbs = List<Uint8List?>.filled(doc.pagesCount, null));
      for (var i = 1; i <= doc.pagesCount; i++) {
        if (!mounted || !identical(_thumbDoc, doc)) return;
        final page = await doc.getPage(i);
        try {
          final image = await page.render(
            width: 150,
            height: 212,
            format: pdfx.PdfPageImageFormat.png,
          );
          if (image?.bytes != null && mounted) {
            setState(() => _thumbs[i - 1] = image!.bytes);
          }
        } finally {
          await page.close();
        }
      }
    } catch (_) {}
  }

  Future<Uint8List?> _savedPdf() async {
    try {
      return await _viewer?.saveDocument() ?? _bytes;
    } catch (_) {
      return _bytes;
    }
  }

  Future<Uint8List> _withInk(Uint8List bytes) {
    final grouped = <int, List<Stroke>>{};
    for (final entry in _ink.entries) {
      grouped[entry.key] = StrokeCodec.documentToStrokes(entry.value);
    }
    return _pdf.drawSnoteInk(bytes, grouped, sourceSizes: _inkSizes);
  }

  Future<void> _export() async {
    final base = await _savedPdf();
    if (base == null) return;
    final output = await _withInk(base);
    final stem = (_asset?.name ?? 'snote').replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
    final uri = await FilePicker.saveFile(
      fileName: stem + '-annotated.pdf',
      bytes: output,
      mimeType: 'application/pdf',
    );
    if (uri != null && mounted) _snack('Saved annotated PDF to ' + uri.toString());
  }

  Future<void> _share() async {
    final base = await _savedPdf();
    if (base == null) return;
    final output = await _withInk(base);
    await SharePlus.instance.share(
      ShareParams(
        text: _asset?.name ?? 'Snote PDF',
        files: <XFile>[
          XFile.fromData(output, name: 'snote-annotated.pdf', mimeType: 'application/pdf'),
        ],
      ),
    );
  }

  Future<void> _searchPdf() async {
    if (_viewer == null) return;
    final q = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Search PDF text'),
        content: TextField(
          controller: _search,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => Navigator.pop(dialog, v),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Find text',
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, _search.text), child: const Text('Search')),
        ],
      ),
    );
    _search.clear();
    if (q != null && q.trim().isNotEmpty) _viewer?.searchText(q.trim());
  }

  void _setMarkup(_Markup mode) {
    final viewer = _viewer;
    if (viewer == null) return;
    setState(() => _markup = mode);
    viewer.annotationMode = switch (mode) {
      _Markup.highlight => PdfAnnotationMode.highlight,
      _Markup.underline => PdfAnnotationMode.underline,
      _Markup.strikeout => PdfAnnotationMode.strikethrough,
      _Markup.none => PdfAnnotationMode.none,
    };
  }

  Future<void> _edit(Future<Uint8List> Function(Uint8List) op) async {
    final asset = _asset;
    final base = await _savedPdf();
    if (base == null || _loading) return;
    setState(() => _loading = true);
    try {
      final result = await op(await _withInk(base));
      if (asset != null) {
        _asset = await _files.replaceBytes(asset, result) ?? asset;
      }
      if (_asset != null) await _install(result, _asset!);
    } catch (e) {
      if (mounted) _snack('PDF edit failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _insertBlank() => _edit((b) => _pdf.insertBlankPage(b, _page));
  Future<void> _rotate() => _edit((b) => _pdf.rotatePage(b, _page - 1));

  Future<void> _deletePage() async {
    if (_pageCount > 1) await _edit((b) => _pdf.removePage(b, _page - 1));
  }

  Future<void> _crop() async {
    var left = .03;
    var top = .03;
    var right = .03;
    var bottom = .03;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, setDialog) => AlertDialog(
          title: const Text('Crop current page'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _cropSlider('Left', left, (v) => setDialog(() => left = v)),
              _cropSlider('Top', top, (v) => setDialog(() => top = v)),
              _cropSlider('Right', right, (v) => setDialog(() => right = v)),
              _cropSlider('Bottom', bottom, (v) => setDialog(() => bottom = v)),
            ],
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Crop')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _edit((b) => _pdf.cropPage(
        b, _page - 1,
        left: left, top: top, right: right, bottom: bottom,
      ));
    }
  }

  Widget _cropSlider(String label, double value, ValueChanged<double> change) => Row(
    children: <Widget>[
      SizedBox(width: 60, child: Text(label)),
      Expanded(child: Slider(value: value, min: 0, max: .35, onChanged: change)),
    ],
  );

  Future<void> _reorder() async {
    if (_pageCount <= 1) return;
    final order = List<int>.generate(_pageCount, (i) => i + 1);
    final apply = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (_, setSheet) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(
            children: <Widget>[
              const ListTile(
                title: Text('Reorder pages', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text('Drag pages into the order you want.'),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: order.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final value = order.removeAt(oldIndex);
                    order.insert(newIndex, value);
                    setSheet(() {});
                  },
                  itemBuilder: (_, index) => ListTile(
                    key: ValueKey(order[index]),
                    leading: CircleAvatar(child: Text((index + 1).toString())),
                    title: Text('Original page ' + order[index].toString()),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheet, true),
                    child: const Text('Apply'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (apply == true) await _edit((b) => _pdf.reorderPages(b, order));
  }

  Future<void> _editableSnote() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _loading = true);
    try {
      final note = await _notes.create(
        title: 'Editable PDF - ' + (_asset?.name ?? 'Document'),
        folderId: widget.folderId,
      );
      final document = await pdfx.PdfDocument.openData(bytes);
      final pages = <Map<String, Object?>>[];
      try {
        for (var i = 1; i <= document.pagesCount; i++) {
          final page = await document.getPage(i);
          try {
            final image = await page.render(
              width: 1400,
              height: 1980,
              format: pdfx.PdfPageImageFormat.png,
            );
            if (image?.bytes == null) continue;
            final asset = await _files.saveBytes(
              noteId: note.id,
              name: 'pdf-page-' + i.toString() + '.png',
              type: 'pdf-page-image',
              bytes: image!.bytes,
              metadata: <String, dynamic>{'page': i, 'sourcePdf': _asset?.id},
            );
            pages.add(<String, Object?>{
              'id': 'editable-' + DateTime.now().microsecondsSinceEpoch.toString() + '-' + i.toString(),
              'template': 'blank',
              'paperColor': 0xffffffff,
              'lineColor': 0xffffffff,
              'lineOpacity': 0.0,
              'spacing': 28.0,
              'cornellAssist': false,
              'orientation': page.width >= page.height ? 'horizontal' : 'vertical',
              'strokes': <Object?>[],
              'backgroundAssetId': asset.id,
            });
          } finally {
            await page.close();
          }
        }
      } finally {
        await document.close();
      }
      await _notes.saveContent(note.id, <String, Object?>{
        'version': 6,
        'pages': pages,
        'pdfEditable': true,
        'sourcePdfAttachmentId': _asset?.id,
      });
      if (mounted) {
        _snack('Created editable Snote with ' + pages.length.toString() + ' page(s).');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _snack('Conversion failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _inkWorkspace() => LayoutBuilder(
    builder: (_, c) {
      _inkSizes[_page] = Size(c.maxWidth, c.maxHeight);
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (_bytes != null)
            FutureBuilder<_PageRaster?>(
              future: _renderPage(_bytes!, _page),
              builder: (_, snapshot) {
                final image = snapshot.data?.bytes;
                return image == null
                    ? const ColoredBox(color: Colors.white)
                    : Image.memory(image, fit: BoxFit.contain);
              },
            ),
          SnoteCanvas(
            key: ValueKey('pdf-ink-' + _page.toString() + '-' + _inkTool.name),
            pen: PenConfig(type: _inkTool.penType, color: _inkColor, size: _inkSize),
            tool: _inkTool,
            controller: _inkController,
            initialDocument: _inkDocument(_page),
            backgroundColor: Colors.transparent,
            onChanged: (document) => _ink[_page] = document,
          ),
          Positioned(left: 10, right: 10, bottom: 10, child: Center(child: _inkToolbar())),
        ],
      );
    },
  );

  Future<_PageRaster?> _renderPage(Uint8List bytes, int pageNumber) async {
    try {
      final document = await pdfx.PdfDocument.openData(bytes);
      final page = await document.getPage(pageNumber);
      try {
        final image = await page.render(
          width: 1400,
          height: 1980,
          format: pdfx.PdfPageImageFormat.png,
        );
        if (image?.bytes == null) return null;
        return _PageRaster(image!.bytes);
      } finally {
        await page.close();
        await document.close();
      }
    } catch (_) {
      return null;
    }
  }

  Widget _inkToolbar() {
    const tools = <CanvasTool>[
      CanvasTool.ballpoint,
      CanvasTool.fountain,
      CanvasTool.calligraphy,
      CanvasTool.pencil,
      CanvasTool.highlighter,
      CanvasTool.eraser,
      CanvasTool.pixelEraser,
      CanvasTool.lasso,
    ];
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final tool in tools)
              IconButton(
                tooltip: tool.label,
                onPressed: () => setState(() => _inkTool = tool),
                icon: Icon(_toolIcon(tool)),
              ),
            IconButton(onPressed: _inkColorSheet, icon: Icon(Icons.color_lens_outlined, color: _inkColor)),
            IconButton(onPressed: _inkSizeSheet, icon: const Icon(Icons.line_weight_rounded)),
          ],
        ),
      ),
    );
  }

  IconData _toolIcon(CanvasTool tool) {
    switch (tool) {
      case CanvasTool.ballpoint: return Icons.edit_rounded;
      case CanvasTool.fountain: return Icons.gesture_rounded;
      case CanvasTool.calligraphy: return Icons.format_italic_rounded;
      case CanvasTool.pencil: return Icons.brush_rounded;
      case CanvasTool.highlighter: return Icons.highlight_rounded;
      case CanvasTool.eraser: return Icons.auto_fix_normal_rounded;
      case CanvasTool.pixelEraser: return Icons.auto_fix_high_rounded;
      case CanvasTool.lasso: return Icons.gesture_rounded;
      default: return Icons.edit_rounded;
    }
  }

  Future<void> _inkColorSheet() async {
    const colors = <Color>[
      Color(0xff111827), Color(0xffdc2626), Color(0xffea580c),
      Color(0xffca8a04), Color(0xff16a34a), Color(0xff0284c7),
      Color(0xff4f46e5), Color(0xff9333ea), Color(0xffdb2777),
    ];
    final color = await showModalBottomSheet<Color>(
      context: context,
      builder: (sheet) => Wrap(
        padding: const EdgeInsets.all(18),
        spacing: 12,
        children: colors.map((c) => InkWell(
          onTap: () => Navigator.pop(sheet, c),
          child: CircleAvatar(backgroundColor: c),
        )).toList(),
      ),
    );
    if (color != null) setState(() => _inkColor = color);
  }

  Future<void> _inkSizeSheet() async {
    var size = _inkSize;
    final result = await showModalBottomSheet<double>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (_, setSheet) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('Thickness ' + size.toStringAsFixed(1)),
              Slider(value: size, min: .5, max: 32, divisions: 126, onChanged: (v) => setSheet(() => size = v)),
              FilledButton(onPressed: () => Navigator.pop(sheet, size), child: const Text('Apply')),
            ],
          ),
        ),
      ),
    );
    if (result != null) setState(() => _inkSize = result);
  }

  Widget _thumbView() => SizedBox(
    width: 152,
    child: ListView.separated(
      padding: const EdgeInsets.all(9),
      itemCount: _thumbs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (_, index) => InkWell(
        onTap: () {
          if (_inkMode) {
            setState(() => _page = index + 1);
          } else {
            _viewer?.jumpToPage(index + 1);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _page == index + 1 ? Theme.of(context).colorScheme.primary : Colors.black12,
              width: _page == index + 1 ? 2 : 1,
            ),
          ),
          child: _thumbs[index] == null
              ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
              : Image.memory(_thumbs[index]!, fit: BoxFit.contain),
        ),
      ),
    ),
  );

  Widget _reader() => _viewer == null
      ? Center(
          child: _loading
              ? const CircularProgressIndicator()
              : FilledButton.icon(onPressed: _importPdf, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Import PDF')),
        )
      : Stack(
          fit: StackFit.expand,
          children: <Widget>[
            SfPdfViewer.memory(
              _bytes!,
              key: ValueKey(_revision),
              controller: _viewer!,
              canShowTextSelectionMenu: true,
              enableTextSelection: true,
              canShowPaginationDialog: true,
              onDocumentLoaded: (details) {
                if (mounted) setState(() => _pageCount = details.document.pages.count);
              },
              onPageChanged: (details) {
                if (mounted) setState(() => _page = details.newPageNumber);
              },
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text('Page ' + _page.toString() + '/' + (_pageCount == 0 ? '?' : _pageCount.toString())),
                ),
              ),
            ),
          ],
        );

  Future<void> _actions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(leading: const Icon(Icons.add_box_outlined), title: const Text('Insert blank page'), onTap: () { Navigator.pop(sheet); _insertBlank(); }),
            ListTile(leading: const Icon(Icons.rotate_90_degrees_ccw_rounded), title: const Text('Rotate page'), onTap: () { Navigator.pop(sheet); _rotate(); }),
            ListTile(leading: const Icon(Icons.crop_rounded), title: const Text('Crop page'), onTap: () { Navigator.pop(sheet); _crop(); }),
            ListTile(leading: const Icon(Icons.swap_vert_rounded), title: const Text('Reorder pages'), onTap: () { Navigator.pop(sheet); _reorder(); }),
            if (_pageCount > 1) ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Delete page'), onTap: () { Navigator.pop(sheet); _deletePage(); }),
            ListTile(leading: const Icon(Icons.auto_stories_outlined), title: const Text('PDF → editable Snote'), onTap: () { Navigator.pop(sheet); _editableSnote(); }),
            ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Export annotated PDF'), onTap: () { Navigator.pop(sheet); _export(); }),
            ListTile(leading: const Icon(Icons.share_outlined), title: const Text('Share annotated PDF'), onTap: () { Navigator.pop(sheet); _share(); }),
          ],
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final content = _inkMode ? _inkWorkspace() : _reader();
    return Scaffold(
      appBar: AppBar(
        title: Text(_asset?.name ?? 'PDF workspace'),
        actions: <Widget>[
          IconButton(tooltip: 'Import PDF', onPressed: _importPdf, icon: const Icon(Icons.picture_as_pdf_outlined)),
          IconButton(tooltip: 'Search text', onPressed: _viewer == null ? null : _searchPdf, icon: const Icon(Icons.search_rounded)),
          PopupMenuButton<String>(
            tooltip: 'Text markup',
            enabled: _viewer != null,
            onSelected: (value) {
              switch (value) {
                case 'highlight': _setMarkup(_Markup.highlight);
                case 'underline': _setMarkup(_Markup.underline);
                case 'strikeout': _setMarkup(_Markup.strikeout);
                case 'none': _setMarkup(_Markup.none);
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'highlight', child: Text('Highlight')),
              PopupMenuItem(value: 'underline', child: Text('Underline')),
              PopupMenuItem(value: 'strikeout', child: Text('Strikeout')),
              PopupMenuItem(value: 'none', child: Text('Stop markup')),
            ],
            icon: const Icon(Icons.highlight_outlined),
          ),
          IconButton(
            tooltip: _inkMode ? 'PDF reader' : 'Pen / eraser / lasso',
            onPressed: _viewer == null ? null : () => setState(() => _inkMode = !_inkMode),
            icon: Icon(_inkMode ? Icons.picture_as_pdf_outlined : Icons.edit_outlined),
          ),
          IconButton(tooltip: 'Thumbnails', onPressed: _viewer == null ? null : () => setState(() => _showThumbs = !_showThumbs), icon: const Icon(Icons.view_sidebar_outlined)),
          IconButton(tooltip: 'More PDF actions', onPressed: _viewer == null ? null : _actions, icon: const Icon(Icons.more_horiz_rounded)),
        ],
      ),
      body: _viewer != null && _showThumbs
          ? Row(children: <Widget>[_thumbView(), Expanded(child: content)])
          : content,
      bottomNavigationBar: _viewer == null
          ? null
          : SafeArea(
              child: SizedBox(
                height: 56,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    children: <Widget>[
                      FilledButton.tonalIcon(onPressed: _insertBlank, icon: const Icon(Icons.add_box_outlined), label: const Text('Blank')),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(onPressed: _editableSnote, icon: const Icon(Icons.auto_stories_outlined), label: const Text('Editable Snote')),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(onPressed: _export, icon: const Icon(Icons.download_outlined), label: const Text('Export')),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _viewer?.dispose();
    _thumbDoc?.close();
    _inkController.dispose();
    _search.dispose();
    super.dispose();
  }
}

class _PageRaster {
  final Uint8List bytes;
  const _PageRaster(this.bytes);
}
