import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SnoteSettings extends ChangeNotifier {
  SnoteSettings._();
  static final instance = SnoteSettings._();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Map<String, dynamic> _values = <String, dynamic>{};

  static const Map<String, bool> boolDefaults = {
    'autoRecognition': true,
    'independentGraphColor': true,
    'longPressMenu': true,
    'selectionMenuOnTouch': true,
    'eraseClickSwitch': true,
    'stylusDoubleTapUndo': true,
    'fingerLongPressSelection': true,
    'showAuxiliaryLine': true,
    'autoAuxiliaryPoint': true,
    'pressureErase': true,
    'pressureEraseArea': true,
    'volumeKeyTurnPage': false,
    'keepScreenOn': false,
    'bookshelfStartPage': true,
    'showPageNavigation': true,
    'showPageNumbers': true,
    'showVisitedHistory': true,
    'showPagePreview': true,
    'showUndoOnRight': false,
    'screenshotNotification': false,
    'clickHyperlink': true,
    'doubleClickHyperlink': true,
    'jumpToNewPage': true,
    'showPenCaseStrokeSize': false,
    'horizontalContinuousScroll': true,
    'showPenFloatSettings': true,
    'autoSyncNote': true,
    'autoBackupLocal': true,
    'writingPostureRightHand': true,
    'disableBackGesture': false,
    'turnOffPush': false,
    'pageSwipe': true,
    'autoAddPage': true,
    'securePagePreviews': true,
    'eInk': false,
    'grayscaleEInk': true,
    'reduceMotion': false,
  };

  static const Map<String, double> doubleDefaults = {
    'pressureEraseThreshold': 0.35,
  };

  bool getBool(String key) => (_values[key] as bool?) ?? boolDefaults[key] ?? false;
  double getDouble(String key) => (_values[key] as num?)?.toDouble() ?? doubleDefaults[key] ?? 0;

  Future<void> load() async {
    for (final item in boolDefaults.entries) {
      final value = await _storage.read(key: 'snote.setting.' + item.key);
      if (value != null) _values[item.key] = value == 'true';
    }
    for (final item in doubleDefaults.entries) {
      final value = await _storage.read(key: 'snote.setting.' + item.key);
      if (value != null) _values[item.key] = double.tryParse(value) ?? item.value;
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
}
