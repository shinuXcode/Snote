import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:share_plus/share_plus.dart';

import '../../canvas_engine/models/pen_config.dart';
import '../../canvas_engine/widgets/page_background.dart';
import '../../canvas_engine/widgets/snote_canvas.dart';
import '../../core/settings/app_settings.dart';
import '../../data/local/file_document_repository.dart';
import '../../data/local/folder_repository.dart';
import '../../data/local/note_repository.dart';

class PdfAnnotationPage extends StatefulWidget {
  final String? folderId;
  const PdfAnnotationPage({super.key, this.folderId});

  @override
  State<PdfAnnotationPage> createState() => _PdfAnnotationPageState();
}

class _PdfAnnotationPageState extends State<PdfAnnotationPage> {
  final _documents = FileDocumentRepository();
  final _notes = NoteRepository();
  final _folders = FolderRepository();
  final _settings = SnoteSettings.instance;

  PdfControllerPinch? _controller;
  Uint8List? _bytes;
  DocumentAsset? _asset;
  LocalNote? _note;
  PageTemplate _template = PageTemplate.blank;

  bool _splitScreen = false;
  bool _selectionMode = false;
  bool _busy = false;
  int _pageCount = 0;
  int _page = 1;
  final Set<int> _selectedPages = <int>{};

  Future<void> _openPdf() async {
    if (_busy) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final note = await _notes.create(
        title: file.name.replaceFirst(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        ),
        folderId: widget.folderId,
      );
      final asset = await _documents.saveBytes(
        noteId: note.id,
        name: file.name,
        type: 'pdf',
        bytes: bytes,
        metadata: <String, dynamic>{'source': 'pdf-import', 'isCover': true},
      );

      final controller = PdfControllerPinch(document: PdfDocument.openData(bytes));
      if (!mounted) {
        controller.dispose();
        await _documents.delete(asset);
        await _notes.delete(note.id);
        return;
      }

      _controller?.dispose();
      setState(() {
        _bytes = bytes;
        _asset = asset;
        _note = note;
        _controller = controller;
        _pageCount = controller.pagesCount ?? 0;
        _page = 1;
        _selectedPages.clear();
        _selectionMode = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf() async {
    final bytes = _bytes;
    final asset = _asset;
    if (bytes == null || asset == null) return;

    final uri = await FilePicker.saveFile(
      fileName: asset.name,
      bytes: bytes,
      mimeType: 'application/pdf',
    );
    if (uri != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ' + uri.toString())),
      );
    }
  }

  Future<void> _sharePdf() async {
    final bytes = _bytes;
    final asset = _asset;
    if (bytes == null || asset == null) return;

    await SharePlus.instance.share(
      ShareParams(
        text: asset.name,
        files: <XFile>[
          XFile.fromData(
            bytes,
            name: asset.name,
            mimeType: 'application/pdf',
          ),
        ],
      ),
    );
  }

  Future<String?> _pickFolder() async {
    final roots = await _folders.listAllVisible();
    if (!mounted) return null;

    return showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            const ListTile(
              title: Text(
                'Choose destination',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              subtitle: Text('Move or copy this PDF into a notebook folder.'),
            ),
            ListTile(
              leading: const Icon(Icons.home_work_outlined),
              title: const Text('Root / All notes'),
              onTap: () => Navigator.pop(sheetContext, '__ROOT__'),
            ),
            ...roots.map(
              (folder) => ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(folder.name),
                onTap: () => Navigator.pop(sheetContext, folder.id),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _movePdf({required bool copy}) async {
    final asset = _asset;
    final note = _note;
    if (asset == null || note == null) return;

    final destination = await _pickFolder();
    if (destination == null) return;
    final folderId = destination == '__ROOT__' ? null : destination;

    try {
      if (copy) {
        final clone = await _notes.create(
          title: note.title + ' copy',
          folderId: folderId,
        );
        await _documents.duplicate(asset, clone.id);
      } else {
        await _notes.moveToFolder(note.id, folderId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(copy ? 'PDF copied.' : 'PDF moved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Operation failed: $error')),
        );
      }
    }
  }

  Future<void> _cutPdf() => _movePdf(copy: false);

  Future<void> _deletePdf() async {
    final asset = _asset;
    final note = _note;
    if (asset == null || note == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete PDF?'),
        content: Text('Move "' + asset.name + '" to the notebook trash?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _documents.delete(asset);
    await _notes.delete(note.id);
    if (mounted) Navigator.maybePop(context);
  }

  Future<void> _toggleCover() async {
    final asset = _asset;
    if (asset == null) return;

    await _documents.setCover(asset.id, !asset.isCover);
    if (!mounted) return;

    setState(() {
      _asset = DocumentAsset(
        id: asset.id,
        noteId: asset.noteId,
        type: asset.type,
        localPath: asset.localPath,
        name: asset.name,
        size: asset.size,
        isCover: !asset.isCover,
        metadata: <String, dynamic>{
          ...asset.metadata,
          'isCover': !asset.isCover,
        },
      );
    });
  }

  Future<void> _selectPages() async {
    final total = _pageCount > 0
        ? _pageCount
        : (_controller?.pagesCount ?? 0);
    if (total <= 0) return;

    var draft = Set<int>.from(_selectedPages);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Select pages'),
          content: SizedBox(
            width: 360,
            height: 380,
            child: ListView.builder(
              itemCount: total,
              itemBuilder: (_, index) {
                final page = index + 1;
                return CheckboxListTile(
                  value: draft.contains(page),
                  onChanged: (value) {
                    setDialog(() {
                      if (value == true) {
                        draft.add(page);
                      } else {
                        draft.remove(page);
                      }
                    });
                  },
                  title: Text('Page ' + page.toString()),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                setState(() {
                  _selectedPages
                    ..clear()
                    ..addAll(draft);
                  _selectionMode = _selectedPages.isNotEmpty;
                });
                Navigator.pop(dialogContext);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  void _selectAll() {
    final total = _pageCount > 0
        ? _pageCount
        : (_controller?.pagesCount ?? 0);
    if (total <= 0) return;

    setState(() {
      _selectedPages
        ..clear()
        ..addAll(List<int>.generate(total, (index) => index + 1));
      _selectionMode = true;
    });
  }

  void _invertSelection() {
    final total = _pageCount > 0
        ? _pageCount
        : (_controller?.pagesCount ?? 0);
    if (total <= 0) return;

    setState(() {
      final next = <int>{};
      for (var page = 1; page <= total; page++) {
        if (!_selectedPages.contains(page)) next.add(page);
      }
      _selectedPages
        ..clear()
        ..addAll(next);
      _selectionMode = next.isNotEmpty;
    });
  }

  Future<void> _templatePicker() async {
    final templates = PageTemplate.values;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => GridView.builder(
        padding: const EdgeInsets.all(18),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.35,
        ),
        itemCount: templates.length,
        itemBuilder: (_, index) {
          final template = templates[index];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() => _template = template);
              Navigator.pop(sheetContext);
            },
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _template == template
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black12,
                  width: _template == template ? 2 : 1,
                ),
              ),
              child: CustomPaint(
                painter: PageBackground(
                  template: template,
                  paperColor: Colors.white,
                  lineColor: Colors.blueGrey,
                  spacing: 18,
                  lineOpacity: .8,
                ),
                child: Center(
                  child: Text(
                    template.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _actions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            if (_asset != null)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('Move'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _movePdf(copy: false);
                },
              ),
            if (_asset != null)
              ListTile(
                leading: const Icon(Icons.copy_all_outlined),
                title: const Text('Copy'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _movePdf(copy: true);
                },
              ),
            if (_asset != null)
              ListTile(
                leading: const Icon(Icons.content_cut_rounded),
                title: const Text('Cut'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _cutPdf();
                },
              ),
            ListTile(
              leading: const Icon(Icons.checklist_rtl_rounded),
              title: Text(_selectionMode ? 'Edit page selection' : 'Select'),
              onTap: () {
                Navigator.pop(sheetContext);
                _selectPages();
              },
            ),
            ListTile(
              leading: const Icon(Icons.select_all_rounded),
              title: const Text('Select all'),
              onTap: () {
                Navigator.pop(sheetContext);
                _selectAll();
              },
            ),
            ListTile(
              leading: const Icon(Icons.flip_to_back_rounded),
              title: const Text('Invert selection'),
              onTap: () {
                Navigator.pop(sheetContext);
                _invertSelection();
              },
            ),
            if (_asset != null)
              ListTile(
                leading: const Icon(Icons.ios_share_rounded),
                title: const Text('Share'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sharePdf();
                },
              ),
            if (_asset != null)
              ListTile(
                leading: Icon(
                  _asset!.isCover
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                ),
                title: Text(
                  _asset!.isCover ? 'Remove cover' : 'Set as cover',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _toggleCover();
                },
              ),
            ListTile(
              leading: Icon(
                _splitScreen
                    ? Icons.splitscreen_rounded
                    : Icons.view_column_outlined,
              ),
              title: Text(
                _splitScreen ? 'Close split screen' : 'Split screen',
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _splitScreen = !_splitScreen);
              },
            ),
            if (_asset != null)
              ListTile(
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('Export'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _exportPdf();
                },
              ),
            if (_asset != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _deletePdf();
                },
              ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Template'),
              onTap: () {
                Navigator.pop(sheetContext);
                _templatePicker();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdfView() {
    final controller = _controller;
    if (controller == null) {
      return Center(
        child: _busy
            ? const CircularProgressIndicator()
            : FilledButton.icon(
                onPressed: _openPdf,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Choose PDF'),
              ),
      );
    }

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: PdfViewPinch(
            controller: controller,
            scrollDirection: Axis.vertical,
            onDocumentLoaded: (document) {
              if (mounted) {
                setState(() => _pageCount = document.pagesCount);
              }
            },
            onPageChanged: (page) {
              if (mounted) setState(() => _page = page);
            },
          ),
        ),
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(
                'Page ' + _page.toString() + '/' +
                    (_pageCount == 0 ? '?' : _pageCount.toString()),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
        if (_selectionMode)
          Positioned(
            left: 12,
            bottom: 12,
            child: Chip(
              label: Text(_selectedPages.length.toString() + ' selected'),
              deleteIcon: const Icon(Icons.close_rounded),
              onDeleted: () => setState(() {
                _selectedPages.clear();
                _selectionMode = false;
              }),
            ),
          ),
      ],
    );
  }

  Widget _annotationPane() => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CustomPaint(
            painter: PageBackground(
              template: _template,
              paperColor: Colors.white,
              lineColor: Colors.blueGrey,
              spacing: 28,
              lineOpacity: .6,
            ),
          ),
          SnoteCanvas(
            pen: const PenConfig(
              type: PenType.ballpoint,
              color: Colors.indigo,
              size: 3,
            ),
            backgroundColor: Colors.transparent,
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final pdf = _pdfView();

    return Scaffold(
      appBar: AppBar(
        title: Text(_asset?.name ?? 'PDF workspace'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Open PDF',
            onPressed: _openPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
          IconButton(
            tooltip: 'Actions',
            onPressed: _controller == null ? null : _actions,
            icon: const Icon(Icons.more_horiz_rounded),
          ),
        ],
      ),
      body: _splitScreen
          ? Row(
              children: <Widget>[
                Expanded(flex: 3, child: pdf),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: _annotationPane(),
                  ),
                ),
              ],
            )
          : pdf,
      floatingActionButton: _controller == null
          ? null
          : FloatingActionButton.small(
              tooltip: _settings.getBool('showPenFloatSettings')
                  ? 'Quick actions'
                  : 'Actions',
              onPressed: _actions,
              child: const Icon(Icons.tune_rounded),
            ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
