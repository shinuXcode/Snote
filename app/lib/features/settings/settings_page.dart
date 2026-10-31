import 'dart:async';
import 'package:flutter/material.dart';

import '../../canvas_engine/widgets/page_background.dart';
import '../../app/theme_controller.dart';
import '../../core/config/app_version.dart';
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
      Text('Snotee', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
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
            ButtonSegment(value: false, label: Text('App settings'), icon: Icon(Icons.tune_rounded)),
            ButtonSegment(value: true, label: Text('Note settings'), icon: Icon(Icons.draw_rounded)),
          ],
          selected: {_noteOnly},
          onSelectionChanged: (values) => setState(() => _noteOnly = values.first),
        ),
      ),
      if (!_noteOnly) _group('Editor shortcuts', [
        _toggle('editorV2ShowTabs', 'Show tabs', 'Show or hide the note-switching bar between the title bar and toolbar.'),
        _toggle('showTitleBarTimer', 'Show timer in title bar', 'Quick access to timer, alarm and stopwatch.'),
        _toggle('showTitleBarSearch', 'Show Google Search in title bar', 'Open Google Search in the in-app browser.'),
      ]),
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
            Row(children: [
              Icon(Icons.speed_rounded, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('Trigger pressure value', style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
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
                const Row(children: [
                  Icon(Icons.zoom_in_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Note canvas zoom', style: TextStyle(fontWeight: FontWeight.w800)),
                ]),
                Text('${(_settings.getDouble('noteZoom') * 100).round()}%'),
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
      if (_noteOnly) _group('Note Controls & Navigation', [
        _toggle('keepScreenOn', 'Keep screen on', 'Stay awake while writing.'),
        _toggle('bookshelfStartPage', 'Bookshelf as start page', 'Open the notebook library first.'),
        _toggle('showPageNavigation', 'Show page navigation', 'Display previous/next/add controls.'),
        _toggle('showPageNumbers', 'Show page number', 'Number pages automatically.'),
        _toggle('showVisitedHistory', 'Show visited history', 'Remember recent page positions.'),
        _toggle('showPagePreview', 'Show page preview sidebar', 'Keep the thumbnail rail available beside the canvas.'),
        _toggle('highlighterOnTop', 'Draw highlighter above content', 'When enabled, highlight ink appears above inserted images and text.'),
        _pagePreviewSideSelector(),
        _toggle('showUndoOnRight', 'Show undo on the right', 'Mirror undo and redo near navigation.'),
        _toggle('screenshotNotification', 'Notification bar displays screenshot', 'Platform-dependent screenshot feedback.'),
        _toggle('clickHyperlink', 'Click hyperlink to jump', 'Open rich-text hyperlinks.'),
        _toggle('doubleClickHyperlink', 'Double click hyperlink with pen to jump', 'Pen-friendly link activation.'),
        _toggle('jumpToNewPage', 'Jump to new page after add', 'Move to the newly created page.'),
        _toggle('showPenCaseStrokeSize', 'Show pen case stroke size', 'Display current stroke width.'),
        _toggle('horizontalContinuousScroll', 'Horizontal continuous scroll', 'Experimental continuous scrolling.'),
        _toggle('showPenFloatSettings', 'Show pen float settings', 'Keep floating tool customization visible.'),

        _toggle('autoBackupLocal', 'Auto backup note to local', 'Keep local recovery data.'),
        _toggle('writingPostureRightHand', 'Writing posture — right hand', 'Optimize floating controls for right-handed writing.'),
        _toggle('disableBackGesture', 'Disable back gesture', 'Use the visible editor back button.'),
        _toggle('turnOffPush', 'Turn off push', 'Disable non-essential push surfaces.'),
        _toggle('pageSwipe', 'Page swipe navigation', 'Swipe from page edges horizontally or vertically to turn pages.'),
        _toggle('autoAddPage', 'Auto add page', 'Create the next numbered page when swiping past the end.'),
        _toggle('securePagePreviews', 'Preview lock / privacy', 'Hide handwritten content in the page preview rail.'),
      ]),
      if (_noteOnly) _group('New Page Template', [
        _editorV2DefaultPageTemplateSelector(),
        _templateColorSelector(
          key: 'defaultPagePaperColor',
          title: 'Default paper background',
          subtitle: 'Applied to newly inserted pages unless you choose a page-specific color.',
          fallback: const Color(0xffffffff),
        ),
        _templateColorSelector(
          key: 'defaultPageLineColor',
          title: 'Default template line color',
          subtitle: 'Applied to new lined, grid and dot templates.',
          fallback: const Color(0xffd8dee8),
        ),
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
            title: const Text('Snote $snoteVersionName', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Offline-first handwriting and rich-text notes.'),
            onTap: () => showAboutDialog(context: context, applicationName: 'Snote', applicationVersion: snoteVersionName),
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

  IconData _settingsIcon(String value) {
    final key = value.toLowerCase();
    if (key.contains('pressure') || key.contains('eras')) return Icons.speed_rounded;
    if (key.contains('page') || key.contains('swipe') || key.contains('navigation')) return Icons.auto_stories_outlined;
    if (key.contains('pen') || key.contains('stroke') || key.contains('writing')) return Icons.draw_rounded;
    if (key.contains('theme') || key.contains('color') || key.contains('grayscale') || key.contains('e-ink') || key.contains('display')) return Icons.palette_outlined;
    if (key.contains('motion') || key.contains('gesture') || key.contains('long press') || key.contains('double tap')) return Icons.gesture_rounded;
    if (key.contains('sync') || key.contains('backup')) return Icons.cloud_sync_outlined;
    if (key.contains('security') || key.contains('lock') || key.contains('privacy')) return Icons.lock_outline_rounded;
    if (key.contains('hyperlink') || key.contains('link')) return Icons.link_rounded;
    if (key.contains('screenshot') || key.contains('notification') || key.contains('push')) return Icons.notifications_outlined;
    if (key.contains('history') || key.contains('visited')) return Icons.history_rounded;
    if (key.contains('screen')) return Icons.screen_lock_portrait_outlined;
    if (key.contains('recognition') || key.contains('shape')) return Icons.auto_awesome_rounded;
    if (key.contains('book') || key.contains('shelf')) return Icons.menu_book_outlined;
    if (key.contains('select') || key.contains('menu')) return Icons.touch_app_outlined;
    return Icons.tune_rounded;
  }

  Widget _editorV2DefaultPageTemplateSelector() => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.grid_view_rounded),
      title: const Text('Default new-page template'),
      subtitle: const Text('Choose a template for new pages, or inherit the current page.'),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: PageTemplate.values.any(
            (template) => template.name == _settings.getString('editorV2DefaultPageTemplate'),
          )
              ? _settings.getString('editorV2DefaultPageTemplate')
              : 'inherit',
          items: [
            const DropdownMenuItem(value: 'inherit', child: Text('Inherit')),
            ...PageTemplate.values.map(
              (template) => DropdownMenuItem(
                value: template.name,
                child: Text(template.name[0].toUpperCase() + template.name.substring(1)),
              ),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              unawaited(_settings.setString(
                'editorV2DefaultPageTemplate',
                value == 'inherit' ? '' : value,
              ));
              setState(() {});
            }
          },
        ),
      ),
    ),
  );

  Widget _templateColorSelector({
    required String key,
    required String title,
    required String subtitle,
    required Color fallback,
  }) {
    final stored = int.tryParse(_settings.getString(key));
    final selected = stored == null ? null : Color(stored);
    const palette = <Color>[
      Color(0xffffffff), Color(0xfff7f8fa), Color(0xfffff8e7), Color(0xfff4f0e8),
      Color(0xffeaf2ff), Color(0xffe8f5e9), Color(0xffffebee), Color(0xfff3e5f5),
      Color(0xff263238), Color(0xff37474f), Color(0xff546e7a), Color(0xff78909c),
      Color(0xff0d47a1), Color(0xff1565c0), Color(0xff42a5f5), Color(0xff80d8ff),
      Color(0xff004d40), Color(0xff00897b), Color(0xff4db6ac), Color(0xffa7ffeb),
      Color(0xff1b5e20), Color(0xff2e7d32), Color(0xff81c784), Color(0xffc5e1a5),
      Color(0xff4a148c), Color(0xff7b1fa2), Color(0xffba68c8), Color(0xffe1bee7),
      Color(0xffb71c1c), Color(0xffc62828), Color(0xffef5350), Color(0xffff8a80),
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Inherit'),
                  selected: selected == null,
                  onSelected: (_) async {
                    await _settings.setString(key, '');
                    if (mounted) setState(() {});
                  },
                ),
                ...palette.map((color) => InkWell(
                  onTap: () async {
                    await _settings.setString(key, color.toARGB32().toString());
                    if (mounted) setState(() {});
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color.toARGB32() == (selected ?? fallback).toARGB32()
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: color.toARGB32() == (selected ?? fallback).toARGB32() ? 3 : 1,
                      ),
                    ),
                  ),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pagePreviewSideSelector() => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const Icon(Icons.view_sidebar_outlined),
      title: const Text('Page preview position'),
      subtitle: const Text('Choose which side of the writing canvas holds page thumbnails.'),
      trailing: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _settings.getString('editorV2PagePreviewSide') == 'right' ? 'right' : 'left',
          items: const [
            DropdownMenuItem(value: 'left', child: Text('Left')),
            DropdownMenuItem(value: 'right', child: Text('Right')),
          ],
          onChanged: (value) {
            if (value == null) return;
            unawaited(_settings.setString('editorV2PagePreviewSide', value));
            setState(() {});
          },
        ),
      ),
    ),
  );

  Widget _toggle(String key, String title, String subtitle) => SwitchListTile.adaptive(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    secondary: Icon(_settingsIcon(key)),
    value: _settings.getBool(key),
    onChanged: (v) => _settings.setBool(key, v),
    title: Text(title),
    subtitle: Text(subtitle),
  );

  Widget _customToggle({required bool value, required String title, required String subtitle, required ValueChanged<bool> onChanged}) =>
      SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        secondary: Icon(_settingsIcon(title)),
        value: value,
        onChanged: onChanged,
        title: Text(title),
        subtitle: Text(subtitle),
      );

  Future<void> _privateTransfer() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Send whole notebook'),
            subtitle: const Text('Export all notes and folders in an encrypted file'),
            onTap: () => Navigator.pop(sheet, 'send'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_open_rounded),
            title: const Text('Receive notebook'),
            subtitle: const Text('Import an encrypted notebook file'),
            onTap: () => Navigator.pop(sheet, 'receive'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;

    final passwordController = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action == 'send' ? 'Protect notebook transfer' : 'Unlock notebook transfer'),
        content: TextField(
          controller: passwordController,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Transfer password',
            helperText: 'Use the same password on the receiving device (8+ characters).',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, passwordController.text),
            child: Text(action == 'send' ? 'Encrypt and save' : 'Choose file'),
          ),
        ],
      ),
    );
    passwordController.dispose();
    if (!mounted || password == null) return;
    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transfer password must be at least 8 characters.')),
      );
      return;
    }

    final transfer = NotebookTransferService(NoteRepository());
    try {
      if (action == 'send') {
        final uri = await transfer.exportEncryptedPicked(password: password);
        if (uri != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Encrypted notebook file is ready to share.')),
          );
        }
      } else {
        final count = await transfer.importEncryptedPicked(password: password);
        if (mounted && count > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported $count note(s) from the encrypted notebook.')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notebook transfer failed: $error')),
        );
      }
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
