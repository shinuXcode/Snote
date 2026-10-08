import 'package:flutter/material.dart';
import '../../app/theme_controller.dart';
import '../../core/settings/app_settings.dart';
import '../../core/security/e2e_encryption_service.dart';
import '../../data/local/notebook_transfer_service.dart';
import '../../data/local/note_repository.dart';
import '../updates/update_center_page.dart';

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
        _themeStyleSelector(),
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
            subtitle: const Text('Each note can have its own password.'),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('End-to-end encryption', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('Encrypt note payloads before local storage and cloud sync. The recovery passphrase stays on your device.'),
            trailing: FutureBuilder<bool>(
              future: SnoteE2EEncryption.instance.enabled,
              builder: (_, snapshot) => Switch(
                value: snapshot.data ?? false,
                onChanged: (value) => value ? _enableE2E() : _disableE2E(),
              ),
            ),
            onTap: _enableE2E,
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
      _group('Updates & About', [
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
            title: const Text('Snote 1.1.0', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Offline-first handwriting and rich-text notes.'),
            onTap: () => showAboutDialog(context: context, applicationName: 'Snote', applicationVersion: '1.1.0'),
          ),
        ),
      ]),
    ],
  );

  Future<void> _enableE2E() async {
    final controller = TextEditingController();
    final recovery = TextEditingController();
    final existing = await SnoteE2EEncryption.instance.configured;
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(existing ? 'Update encryption passphrase' : 'Enable end-to-end encryption'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passphrase', helperText: 'Use at least 8 characters.'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: recovery,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Repeat passphrase'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (controller.text != recovery.text) return;
            Navigator.pop(dialog, controller.text);
          }, child: const Text('Enable')),
        ],
      ),
    );
    recovery.dispose();
    controller.dispose();
    if (value == null || value.isEmpty) return;

    try {
      await SnoteE2EEncryption.instance.enable(value);
      await NoteRepository().encryptExistingNotes();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encryption enabled. Keep your recovery passphrase safe.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Encryption setup failed: $error')));
    }
  }

  Future<void> _disableE2E() async {
    try {
      await NoteRepository().decryptExistingNotes();
      await SnoteE2EEncryption.instance.disable();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encryption disabled for future saves. Existing notes were returned to local plaintext.')));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not disable encryption: $error')));
    }
  }

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
            child: Text(style.name[0].toUpperCase() + style.name.substring(1)),
          )).toList(),
          onChanged: (style) {
            if (style != null) _theme.setStyle(style);
          },
        ),
      ),
    ),
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
