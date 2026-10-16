import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../data/local/note_repository.dart';
import '../updates/update_center_page.dart';
import '../onboarding/welcome_guide_page.dart';
import '../share/qr_import_page.dart';
import '../share/qr_transfer_page.dart';
import '../tools/screenshot_import_page.dart';
import '../trash/trash_page.dart';

class SettingsPage extends StatefulWidget {
  final bool noteOnly;
  const SettingsPage({super.key, this.noteOnly = false});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SnoteSettings.instance;
  final _theme = SnoteThemeController.instance;
  final _settingsSearch = TextEditingController();
  bool _noteOnly = false;

  String get _query => _settingsSearch.text.trim().toLowerCase();

  bool _matches(Widget widget) =>
      _query.isEmpty || widget.toStringDeep().toLowerCase().contains(_query);

  @override
  void initState() {
    super.initState();
    _noteOnly = widget.noteOnly;
    _settingsSearch.addListener(_refresh);
    _settings.addListener(_refresh);
    _theme.addListener(_refresh);
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _settingsSearch.dispose();
    _settings.removeListener(_refresh);
    _theme.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: 44,
          child: TextField(
            controller: _settingsSearch,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search settings',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _settingsSearch.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _settingsSearch.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: InputBorder.none,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 900;
        return wide
            ? Row(children: [
                SizedBox(width: 330, child: _sideInfo(context)),
                const VerticalDivider(width: 1),
                Expanded(child: _settingsList(context)),
              ])
            : _settingsList(context);
      }),
    );
  }

  Widget _sideInfo(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 22, 18, 30),
    children: [
      Text('Snote', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Handwriting workspace controls, display comfort and privacy settings.'),
      const SizedBox(height: 24),
      _infoCard(context, Icons.draw_rounded, 'Writing first', 'Stylus ink is rendered from an in-place stroke buffer so pointer movement does not rebuild the whole editor.'),
      _infoCard(context, Icons.lock_outline_rounded, 'Note password', 'Note Lock is per-note and separate from the device screen lock. Biometric note lock is not used.'),
      _infoCard(context, Icons.auto_awesome_rounded, 'Physical E-Ink mode', 'Neutral grayscale, low-contrast surfaces and reduced visual motion simulate a physical e-ink presentation without adding a warm tint.'),
    ],
  );

  Widget _infoCard(BuildContext context, IconData icon, String title, String text) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(child: Icon(icon)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(text),
        ])),
      ]),
    ),
  );

  Widget _settingsList(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('More settings'), icon: Icon(Icons.tune_rounded)),
            ButtonSegment(value: true, label: Text('Note settings'), icon: Icon(Icons.draw_rounded)),
          ],
          selected: {_noteOnly},
          onSelectionChanged: (values) => setState(() => _noteOnly = values.first),
        ),
      ),
      if (_noteOnly) _group('Writing Operation', [
        _toggle('autoRecognition', 'Auto Recognition', 'Recognize a drawn shape after a short hold.'),
        _toggle('palmRejection', 'Palm rejection', 'Ignore accidental finger touches while writing with a stylus. Turn this off to allow finger drawing.'),
        _toggle('independentGraphColor', 'Independent graph color / stroke', 'Keep graph and stroke styling separate.'),
        _toggle('longPressMenu', 'Long press to show menu', 'Use a long press for quick pen tools and selection.'),
        _toggle('selectionMenuOnTouch', 'Show menu by touch in selection mode', 'Touch empty canvas to reopen selection controls.'),
        _toggle('eraseClickSwitch', 'Erase mode: blank tap switches to pen', 'Return to pen mode when the eraser misses.'),
        _toggle('stylusDoubleTapUndo', 'Stylus double tap undo', 'Double tap the stylus to undo the latest stroke.'),
        _toggle('fingerLongPressSelection', 'Finger long press selection', 'Long press with a finger to enter selection.'),
        _toggle('showAuxiliaryLine', 'Show auxiliary line', 'Display a writing guide.'),
        _toggle('autoAuxiliaryPoint', 'Auto approach to auxiliary point', 'Snap helper points to the guide.'),
        _toggle('pressureErase', 'Pressure erase', 'Use stylus pressure for erasing.'),
        _toggle('pressureEraseArea', 'Erase area changes with pressure', 'Increase eraser radius with pressure.'),
        _toggle('stylusHoldActions', 'Stylus hold actions', 'Hold over ink to select it; hold on blank paper to erase.'),
        _toggle('autoSave', 'Auto-save notes', 'Save automatically after changes. Turn this off to save manually from the editor toolbar.'),
        _toggle('volumeKeyTurnPage', 'Volume key turn page', 'Turn pages with volume keys where the platform exposes the event.'),
      ]),
      if (_noteOnly && (_query.isEmpty || 'trigger pressure value'.contains(_query)))
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 5, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Trigger pressure value', style: TextStyle(fontWeight: FontWeight.w800)),
            Slider(
              value: _settings.getDouble('pressureEraseThreshold'),
              min: .05, max: 1,
              onChanged: (v) => _settings.setDouble('pressureEraseThreshold', v),
            ),
          ]),
        ),
      ),
      if (_noteOnly)
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Note canvas zoom', style: TextStyle(fontWeight: FontWeight.w800)),
                Text((_settings.getDouble('noteZoom') * 100).round().toString() + '%'),
                Slider(
                  value: _settings.getDouble('noteZoom').clamp(.5, 4).toDouble(),
                  min: .5,
                  max: 4,
                  divisions: 14,
                  label: (_settings.getDouble('noteZoom') * 100).round().toString() + '%',
                  onChanged: (value) {
                    setState(() {});
                    unawaited(_settings.setDouble('noteZoom', value));
                  },
                ),
                const Text('Use two fingers to zoom the page; double-tap resets to the selected zoom.'),
              ],
            ),
          ),
        ),
      if (!_noteOnly) _group('Display', [
        _themeModeSelector(),
        _themeStyleSelector(),
        _colorThemeSelector(),
        _customToggle(
          value: _theme.eInk,
          title: 'Physical E-Ink display',
          subtitle: 'Neutral grayscale presentation with reduced visual noise.',
          onChanged: _theme.setEInk,
        ),
        _customToggle(
          value: _theme.grayscale,
          title: 'Strict grayscale output',
          subtitle: 'Remove color from the app display while E-Ink mode is active.',
          onChanged: _theme.setGrayscale,
        ),
        _customToggle(
          value: _theme.reduceMotion,
          title: 'Reduce motion',
          subtitle: 'Minimize transitions and animated surfaces.',
          onChanged: _theme.setReduceMotion,
        ),
      ]),
      if (_noteOnly) _group('Other Settings', [
        _toggle('keepScreenOn', 'Keep screen on', 'Stay awake while writing.'),
        _toggle('bookshelfStartPage', 'Bookshelf as start page', 'Open the notebook library first.'),
        _toggle('showPageNavigation', 'Show page navigation', 'Display previous/next/add controls.'),
        _toggle('showPageNumbers', 'Show page number', 'Number pages automatically.'),
        _toggle('showVisitedHistory', 'Show visited history', 'Remember recent page positions.'),
        _toggle('showPagePreview', 'Show page preview on the right', 'Keep the thumbnail rail available.'),
        _toggle('showUndoOnRight', 'Show undo on the right', 'Mirror undo and redo near navigation.'),
        _toggle('screenshotNotification', 'Notification bar displays screenshot', 'Platform-dependent screenshot feedback.'),
        _toggle('clickHyperlink', 'Click hyperlink to jump', 'Open rich-text hyperlinks.'),
        _toggle('doubleClickHyperlink', 'Double click hyperlink with pen to jump', 'Pen-friendly link activation.'),
        _toggle('jumpToNewPage', 'Jump to new page after add', 'Move to the newly created page.'),
        _toggle('showPenCaseStrokeSize', 'Show pen case stroke size', 'Display current stroke width.'),
        _toggle('horizontalContinuousScroll', 'Horizontal continuous scroll', 'Experimental continuous scrolling.'),
        _toggle('showPenFloatSettings', 'Show pen float settings', 'Keep floating tool customization visible.'),
        _toggle('autoSyncNote', 'Auto sync note', 'Queue and synchronize local changes when available.'),
        _toggle('autoBackupLocal', 'Auto backup note to local', 'Keep local recovery data.'),
        _toggle('writingPostureRightHand', 'Writing posture — right hand', 'Optimize floating controls for right-handed writing.'),
        _toggle('disableBackGesture', 'Disable back gesture', 'Use the visible editor back button.'),
        _toggle('turnOffPush', 'Turn off push', 'Disable non-essential push surfaces.'),
        _toggle('pageSwipe', 'Page swipe navigation', 'Swipe left/right to navigate pages.'),
        _toggle('autoAddPage', 'Auto add page', 'Create the next numbered page when swiping past the end.'),
        _toggle('securePagePreviews', 'Preview lock / privacy', 'Hide handwritten content in the page preview rail.'),
      ]),
      if (!_noteOnly && (_query.isEmpty || 'privacy security custom note password'.contains(_query))) _group('Privacy & Security', [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Custom note password', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Each note can have its own password. This is not your device screen lock and does not use biometric authentication.'),
          ),
        ),
      ]),
      if (!_noteOnly && (_query.isEmpty || 'private transfer qr screenshot bin trash import export notes'.contains(_query))) _group('Notebook & File Management', [
        Card(child: ListTile(
          leading: const Icon(Icons.qr_code_2_rounded),
          title: const Text('Private transfer'),
          subtitle: const Text('Send a note using local QR frames or receive a QR transfer. No cloud upload.'),
          onTap: _privateTransfer,
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.image_outlined),
          title: const Text('Screenshot to note'),
          subtitle: const Text('Capture or import a screenshot into a note.'),
          onTap: _openScreenshotImport,
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.delete_outline_rounded),
          title: const Text('Bin / recently deleted'),
          subtitle: const Text('Restore or permanently delete trashed notes.'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage())),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.import_export_rounded),
          title: const Text('Import / export notes'),
          subtitle: const Text('Portable Snote package, JSON and text formats.'),
          onTap: _transfer,
        )),
      ]),
      if (!_noteOnly && (_query.isEmpty || 'updates about release app notices'.contains(_query))) _group('Updates & About', [
        Card(child: ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Welcome & user guide'),
          subtitle: const Text('Reopen the guide to folders, handwriting, PDFs, flashcards, mind maps and privacy.'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WelcomeGuidePage())),
        )),
        Card(
          child: ListTile(
            leading: const Icon(Icons.system_update_alt_rounded),
            title: const Text('Updates & notifications', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Check releases, open the update page and review app notices.'),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateCenterPage())),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Snote 0.7.0', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Offline-first handwriting and rich-text notes.'),
            onTap: () => showAboutDialog(context: context, applicationName: 'Snote', applicationVersion: '1.0.0'),
          ),
        ),
      ]),
    ],
  );

  Widget _themeModeSelector() => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appearance mode', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Choose light, dark, or follow the device.'),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.settings_suggest_outlined)),
              ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
            ],
            selected: {_theme.themeMode},
            onSelectionChanged: (values) => _theme.setThemeMode(values.first),
          ),
        ],
      ),
    ),
  );

  Widget _colorThemeSelector() => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.color_lens_outlined),
      title: const Text('App color theme', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(_theme.colorTheme.label),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<SnoteColorTheme>(
          value: _theme.colorTheme,
          items: SnoteColorTheme.values.map((theme) => DropdownMenuItem(
            value: theme,
            child: Text(theme.label),
          )).toList(),
          onChanged: (theme) {
            if (theme != null) _theme.setColorTheme(theme);
          },
        ),
      ),
    ),
  );

  Widget _themeStyleSelector() => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Interface profile', style: TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(_theme.style.name),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<SnoteThemeStyle>(
          value: _theme.style,
          items: SnoteThemeStyle.values.map((style) => DropdownMenuItem(
            value: style,
            child: Text(switch (style) {
              SnoteThemeStyle.standard => 'Standard',
              SnoteThemeStyle.apple => 'Apple',
              SnoteThemeStyle.windows => 'Windows',
              SnoteThemeStyle.mac => 'macOS',
              SnoteThemeStyle.linux => 'Linux',
              SnoteThemeStyle.mobile => 'Mobile',
              SnoteThemeStyle.tablet => 'Tablet',
            }),
          )).toList(),
          onChanged: (style) {
            if (style != null) _theme.setStyle(style);
          },
        ),
      ),
    ),
  );

  Widget _group(String title, List<Widget> children) {
    final visibleChildren = _query.isEmpty || title.toLowerCase().contains(_query)
        ? children
        : children.where(_matches).toList();
    if (visibleChildren.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(title.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
        ),
        Card(child: Column(children: visibleChildren)),
      ],
    );
  }

  Widget _toggle(String key, String title, String subtitle) => SwitchListTile.adaptive(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    value: _settings.getBool(key),
    onChanged: (v) => _settings.setBool(key, v),
    title: Text(title),
    subtitle: Text(subtitle),
  );

  Widget _customToggle({required bool value, required String title, required String subtitle, required ValueChanged<bool> onChanged}) =>
      SwitchListTile.adaptive(contentPadding: const EdgeInsets.symmetric(horizontal: 16), value: value, onChanged: onChanged, title: Text(title), subtitle: Text(subtitle));

  Future<void> _privateTransfer() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const Icon(Icons.qr_code_scanner_rounded), title: const Text('Receive note'), subtitle: const Text('Open the QR receiver'), onTap: () => Navigator.pop(sheet, 'receive')),
        ListTile(leading: const Icon(Icons.qr_code_2_rounded), title: const Text('Send note'), subtitle: const Text('Choose a note to display transfer QR codes'), onTap: () => Navigator.pop(sheet, 'send')),
      ])),
    );
    if (!mounted || action == null) return;
    if (action == 'receive') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const QrImportPage()));
      return;
    }
    final notes = await NoteRepository().listAllVisible();
    if (!mounted) return;
    final selected = await showModalBottomSheet<LocalNote>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .7,
        child: ListView(
          children: [
            const ListTile(title: Text('Choose note to send', style: TextStyle(fontWeight: FontWeight.w800))),
            for (final note in notes)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(note.title.isEmpty ? 'Untitled note' : note.title),
                subtitle: Text(note.noteType),
                onTap: () => Navigator.pop(sheet, note),
              ),
          ],
        ),
      )),
    );
    if (selected != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => QrTransferPage(note: selected)));
    }
  }

  Future<void> _openScreenshotImport() async {
    if (!mounted) return;
    // Screenshot import creates a new note; an empty folder context is intentional here.
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ScreenshotImportPage()));
  }

  Future<void> _transfer() async {
    final messenger = ScaffoldMessenger.of(context);
    final transfer = NotebookTransferService(NoteRepository());
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('Import notes'),
            subtitle: const Text('JSON, Snote, ZIP, GoodNotes/TouchNotes archive, Markdown, TXT, CSV, TSV'),
            onTap: () => Navigator.pop(sheetContext, 'import'),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export portable package'),
            subtitle: const Text('Snote ZIP with folders and note data'),
            onTap: () => Navigator.pop(sheetContext, 'export'),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('Export JSON'),
            onTap: () => Navigator.pop(sheetContext, 'json'),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Export Markdown'),
            onTap: () => Navigator.pop(sheetContext, 'markdown'),
          ),
          ListTile(
            leading: const Icon(Icons.text_snippet_outlined),
            title: const Text('Export plain text'),
            onTap: () => Navigator.pop(sheetContext, 'text'),
          ),
        ]),
      ),
    );
    try {
      if (action == 'import') {
        final count = await transfer.importPicked();
        if (mounted) messenger.showSnackBar(SnackBar(content: Text('Imported $count note(s).')));
      } else if (action == 'export') {
        final path = await transfer.exportPicked();
        if (path != null && mounted) messenger.showSnackBar(SnackBar(content: Text('Exported: $path')));
      } else if (action == 'json') {
        final path = await transfer.exportJsonPicked();
        if (path != null && mounted) messenger.showSnackBar(SnackBar(content: Text('Exported: $path')));
      } else if (action == 'markdown') {
        final path = await transfer.exportMarkdownPicked();
        if (path != null && mounted) messenger.showSnackBar(SnackBar(content: Text('Exported: $path')));
      } else if (action == 'text') {
        final path = await transfer.exportTextPicked();
        if (path != null && mounted) messenger.showSnackBar(SnackBar(content: Text('Exported: $path')));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
