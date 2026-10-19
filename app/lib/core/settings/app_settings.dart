import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SnoteSettings extends ChangeNotifier {
  SnoteSettings._();
  static final instance = SnoteSettings._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Map<String, dynamic> _values = {};

  static const boolDefaults = <String, bool>{
    'autoRecognition': true, 'independentGraphColor': true, 'longPressMenu': true, 'palmRejection': true, 'fingerWritingProtection': true,
    'selectionMenuOnTouch': true, 'eraseClickSwitch': true, 'stylusDoubleTapUndo': true,
    'fingerLongPressSelection': true, 'showAuxiliaryLine': true, 'autoAuxiliaryPoint': true,
    'pressureErase': true, 'pressureEraseArea': true, 'stylusHoldActions': true, 'autoSave': true, 'volumeKeyTurnPage': false,
    'keepScreenOn': false, 'bookshelfStartPage': true, 'showPageNavigation': true,
    'showPageNumbers': true, 'showVisitedHistory': true, 'showPagePreview': true,
    'showUndoOnRight': false, 'screenshotNotification': false, 'clickHyperlink': true,
    'doubleClickHyperlink': true, 'jumpToNewPage': true, 'showPenCaseStrokeSize': false,
    'horizontalContinuousScroll': true, 'showPenFloatSettings': true, 'autoSyncNote': true,
    'autoBackupLocal': true, 'writingPostureRightHand': true, 'disableBackGesture': false,
    'turnOffPush': false, 'pageSwipe': true, 'autoAddPage': true,
    'securePagePreviews': false, 'eInk': false, 'grayscaleEInk': true, 'reduceMotion': false,
    'welcomeGuideSeen': false, 'editorV2FloatingToolbar': false, 'editorV2FavoritesVertical': false, 'editorV2FloatingPageNavigation': false, 'editorV2ShowFavoritesShowcase': true, 'editorV2ShowNoteSwitcher': true, 'editorV2RememberLastPage': true, 'editorV2CompactFullscreenToolbar': true, 'timerAlertEnabled': true, 'showTitleBarTimer': true, 'showTitleBarSearch': true, 'editorV2ShowTabs': true, 'editorV2ToolbarCollapsed': false, 'editorV2FavoriteCollapsed': false, 'editorV2CalculatorCollapsed': false, 'floatingTimerCollapsed': false, 'editorV2ToolbarDimensionsLocked': false,
  };

  static const doubleDefaults = <String, double>{
    'pressureEraseThreshold': .35,
    'strokeSmoothing': .72,
    'velocitySensitivity': .65,
    'pressureExponent': 1.0,
    'noteZoom': 1.0,
    'toolPencaseX': -1.0,
    'toolPencaseY': 170.0,
    'editorV2ToolbarLength': 360.0,
    'editorV2ToolbarThickness': 34.0,
    'editorV2ToolbarMarginLeft': 0.0,
    'editorV2ToolbarMarginTop': 0.0,
    'editorV2ToolbarMarginRight': 0.0,
    'editorV2ToolbarMarginBottom': 0.0,
    'editorV2ToolbarPaddingLeft': 2.0,
    'editorV2ToolbarPaddingTop': 1.0,
    'editorV2ToolbarPaddingRight': 2.0,
    'editorV2ToolbarPaddingBottom': 1.0,
  };

  static const stringDefaults = <String, String>{
    'themeStyle': 'standard',
    'toolbarDock': 'left',
    'toolbarToolbox': 'compact',
    'eInkProfile': 'physical',
    'defaultPageTemplate': 'dotted',
    'defaultPaperPalette': 'paper-white',
    'pencaseTools': 'ballpoint,fountain,pencil,highlighter,marker,brush,eraser,lasso,fill,line,arrow,rectangle,ellipse,cartesianPlane,dashedLine,dottedLine,ruler,compass,protractor,divider',
    'toolPlacements': '{}',
    'editorV2FavoriteShapes': '[]',
    'toolOrder': '[]',
    'toolPencaseDockSide': 'right',
    'toolInstrumentDefaultsV1': '',
    'pencasePresets': '[]',
    'coverLibrary': '[]',
    'folderSort': 'nameAsc',
    'pressureCurve': 'linear', 'editorV2ToolbarDock': 'top', 'editorV2FavoritePens': '[]', 'editorV2ToolProfiles': '{}', 'editorV2ToolPlacements': '{}', 'editorV2ToolbarOrder': '[]',
    'toolSizes': '{}',
    'toolColors': '{}',
    'toolDashed': '{}',
    'lassoStyle': 'solid',
    'eraserMode': 'stroke',
    'timerAlertSound': 'alert',
    'floatingTimerDockSide': 'right',
    'editorV2FavoriteOffset': '{"dx":16,"dy":220}',
    'editorV2SmartPageFavorites': '[]',
    'floatingAlarms': '[]',
  };

  bool getBool(String key) => (_values[key] as bool?) ?? boolDefaults[key] ?? false;
  double getDouble(String key) => (_values[key] as num?)?.toDouble() ?? doubleDefaults[key] ?? 0;
  String getString(String key) => (_values[key] as String?) ?? stringDefaults[key] ?? '';

  Future<void> load() async {
    await _storage.delete(key: 'snote.setting.geminiApiKey');
    for (final entry in boolDefaults.entries) {
      final raw = await _storage.read(key: 'snote.setting.' + entry.key);
      if (raw != null) _values[entry.key] = raw == 'true';
    }
    for (final entry in doubleDefaults.entries) {
      final raw = await _storage.read(key: 'snote.setting.' + entry.key);
      if (raw != null) _values[entry.key] = double.tryParse(raw) ?? entry.value;
    }
    for (final entry in stringDefaults.entries) {
      final raw = await _storage.read(key: 'snote.setting.' + entry.key);
      if (raw != null) _values[entry.key] = raw;
    }
    if (_values['toolInstrumentDefaultsV1'] != 'done') {
      final current = getString('pencaseTools').split(',').where((tool) => tool.isNotEmpty).toList();
      for (final instrument in const ['ruler', 'compass', 'protractor', 'divider']) {
        if (!current.contains(instrument)) current.add(instrument);
      }
      final migrated = current.join(',');
      _values['pencaseTools'] = migrated;
      _values['toolInstrumentDefaultsV1'] = 'done';
      await _storage.write(key: 'snote.setting.pencaseTools', value: migrated);
      await _storage.write(key: 'snote.setting.toolInstrumentDefaultsV1', value: 'done');
    }
    notifyListeners();
  }

  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
    notifyListeners();
    await _storage.write(key: 'snote.setting.' + key, value: value.toString());
  }

  Future<void> setDouble(String key, double value) async {
    _values[key] = value;
    notifyListeners();
    await _storage.write(key: 'snote.setting.' + key, value: value.toString());
  }

  Future<void> setString(String key, String value) async {
    _values[key] = value;
    notifyListeners();
    await _storage.write(key: 'snote.setting.' + key, value: value);
  }
}