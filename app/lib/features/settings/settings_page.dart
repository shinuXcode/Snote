import 'package:flutter/material.dart';
import '../../app/theme_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../data/local/note_repository.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settings = SnoteSettings.instance;
  final _theme = SnoteThemeController.instance;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_refresh);
    _theme.addListener(_refresh);
  }

  void _refresh() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _settings.removeListener(_refresh);
    _theme.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w900))),
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
      _infoCard(context, Icons.auto_awesome_rounded, 'E-Ink simulation', 'Warm paper, grayscale and reduced motion approximate a physical e-ink reading mode on normal displays.'),
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
      _group('Writing Operation', [
        _toggle('autoRecognition', 'Auto Recognition', 'Recognize a drawn shape after a short hold.'),
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
        _toggle('volumeKeyTurnPage', 'Volume key turn page', 'Turn pages with volume keys where the platform exposes the event.'),
      ]),
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
      _group('Display', [
        _customToggle(
          value: _theme.eInk,
          title: 'E-Ink / Paper Eye Comfort',
          subtitle: 'Warm paper palette and lower visual contrast.',
          onChanged: _theme.setEInk,
        ),
        _customToggle(
          value: _theme.grayscale,
          title: 'Physical-style grayscale',
          subtitle: 'Approximate grayscale output on LCD/OLED screens.',
          onChanged: _theme.setGrayscale,
        ),
        _customToggle(
          value: _theme.reduceMotion,
          title: 'Reduce motion',
          subtitle: 'Minimize transitions and animated surfaces.',
          onChanged: _theme.setReduceMotion,
        ),
      ]),
      _group('Other Settings', [
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
      _group('Privacy & Security', [
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Custom note password', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Each note can have its own password. This is not your device screen lock and does not use biometric authentication.'),
          ),
        ),
      ]),
      _group('Notebook Transfer', [
        Card(
          child: ListTile(
            leading: const Icon(Icons.import_export_rounded),
            title: const Text('Import / export notes', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Portable Snote package, JSON and best-effort archive import.'),
            onTap: _transfer,
          ),
        ),
      ]),
      _group('About', [
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Snote 0.5.0', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Offline-first handwriting and rich-text notes.'),
            onTap: () => showAboutDialog(context: context, applicationName: 'Snote', applicationVersion: '0.5.0'),
          ),
        ),
      ]),
    ],
  );

  Widget _group(String title, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(title.toUpperCase(), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
      ),
      Card(child: Column(children: children)),
    ],
  );

  Widget _toggle(String key, String title, String subtitle) => SwitchListTile.adaptive(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    value: _settings.getBool(key),
    onChanged: (v) => _settings.setBool(key, v),
    title: Text(title),
    subtitle: Text(subtitle),
  );

  Widget _customToggle({required bool value, required String title, required String subtitle, required ValueChanged<bool> onChanged}) =>
      SwitchListTile.adaptive(contentPadding: const EdgeInsets.symmetric(horizontal: 16), value: value, onChanged: onChanged, title: Text(title), subtitle: Text(subtitle));

  Future<void> _transfer() async {
    final messenger = ScaffoldMessenger.of(context);
    final transfer = NotebookTransferService(NoteRepository());
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          ListTile(leading: Icon(Icons.file_upload_outlined), title: Text('Import portable package'), subtitle: Text('JSON, .snote, ZIP, GoodNotes/TouchNotes archive'), trailing: Icon(Icons.chevron_right_rounded)),
          ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Export portable package'), trailing: Icon(Icons.chevron_right_rounded)),
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
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
