import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SnoteSettings extends ChangeNotifier {
  SnoteSettings._();
  static final instance = SnoteSettings._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Map<String, dynamic> _values = {};

  static const boolDefaults = <String, bool>{
    'autoRecognition': true, 'independentGraphColor': true, 'longPressMenu': true,
    'selectionMenuOnTouch': true, 'eraseClickSwitch': true, 'stylusDoubleTapUndo': true,
    'fingerLongPressSelection': true, 'showAuxiliaryLine': true, 'autoAuxiliaryPoint': true,
    'pressureErase': true, 'pressureEraseArea': true, 'volumeKeyTurnPage': false,
    'keepScreenOn': false, 'bookshelfStartPage': true, 'showPageNavigation': true,
    'showPageNumbers': true, 'showVisitedHistory': true, 'showPagePreview': true,
    'showUndoOnRight': false, 'screenshotNotification': false, 'clickHyperlink': true,
    'doubleClickHyperlink': true, 'jumpToNewPage': true, 'showPenCaseStrokeSize': false,
    'horizontalContinuousScroll': true, 'showPenFloatSettings': true, 'autoSyncNote': true,
    'autoBackupLocal': true, 'writingPostureRightHand': true, 'disableBackGesture': false,
    'turnOffPush': false, 'pageSwipe': true, 'autoAddPage': true,
    'securePagePreviews': true, 'eInk': false, 'grayscaleEInk': true, 'reduceMotion': false,
  };

  static const doubleDefaults = <String, double>{
    'pressureEraseThreshold': .35,
    'strokeSmoothing': .72,
    'velocitySensitivity': .65,
    'pressureExponent': 1.0,
  };

  static const stringDefaults = <String, String>{
    'themeStyle': 'standard',
    'toolbarDock': 'bottom',
    'toolbarToolbox': 'compact',
    'eInkProfile': 'physical',
    'defaultPageTemplate': 'dotted',
    'defaultPaperPalette': 'paper-white',
    'pencaseTools': 'ballpoint,fountain,pencil,highlighter,marker,brush,eraser,pixelEraser,lasso',
    'pressureCurve': 'linear',
  };

  bool getBool(String key) => (_values[key] as bool?) ?? boolDefaults[key] ?? false;
  double getDouble(String key) => (_values[key] as num?)?.toDouble() ?? doubleDefaults[key] ?? 0;
  String getString(String key) => (_values[key] as String?) ?? stringDefaults[key] ?? '';

  Future<void> load() async {
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