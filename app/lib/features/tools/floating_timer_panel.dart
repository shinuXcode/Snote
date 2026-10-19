import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings/app_settings.dart';
import 'alarm_notification_service.dart';

/// A draggable, edge-collapsible timer and stopwatch overlay for the editor.
class SnoteFloatingTimerPanel extends StatefulWidget {
  final VoidCallback onClose;

  const SnoteFloatingTimerPanel({super.key, required this.onClose});

  @override
  State<SnoteFloatingTimerPanel> createState() =>
      _SnoteFloatingTimerPanelState();
}

class _SnoteFloatingTimerPanelState extends State<SnoteFloatingTimerPanel> {
  Timer? _ticker;
  String _mode = 'timer';
  int _timerMinutes = 25;
  int _timerRemaining = 25 * 60;
  DateTime? _timerDeadline;
  bool _timerRunning = false;
  Duration _stopwatchAccumulated = Duration.zero;
  DateTime? _stopwatchStartedAt;
  bool _stopwatchRunning = false;
  TimeOfDay? _alarmTime;
  DateTime? _alarmDeadline;
  bool _alarmArmed = false;
  List<Map<String, Object?>> _alarms = <Map<String, Object?>>[];
  bool _collapsed = false;
  String _dockSide = 'right';
  Offset _offset = const Offset(12, 76);

  @override
  void initState() {
    super.initState();
    _collapsed = SnoteSettings.instance.getBool('floatingTimerCollapsed');
    _dockSide = SnoteSettings.instance.getString('floatingTimerDockSide') == 'left' ? 'left' : 'right';
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(_loadAlarms());
  }

  Future<void> _loadAlarms() async {
    final raw = SnoteSettings.instance.getString('floatingAlarms');
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _alarms = decoded.whereType<Map>().map((item) =>
          item.map<String, Object?>((key, value) => MapEntry(key.toString(), value))
        ).toList();
      }
    } catch (error) {
      debugPrint('[Snote][Alarm] saved alarms could not be decoded: $error');
    }
    try {
      await AlarmNotificationService.instance.rescheduleAll(_alarms);
    } catch (error) {
      debugPrint('[Snote][Alarm] restore scheduling failed: $error');
    }
    if (mounted) setState(() {});
  }

  Future<void> _persistAlarms() async {
    await SnoteSettings.instance.setString('floatingAlarms', jsonEncode(_alarms));
  }

  Future<void> _addSavedAlarm() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Choose alarm time',
    );
    if (picked == null || !mounted) return;
    final titleController = TextEditingController(text: 'Snote alarm');
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Name alarm'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Alarm name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, titleController.text.trim()), child: const Text('Continue')),
        ],
      ),
    );
    titleController.dispose();
    if (title == null || !mounted) return;
    final repeat = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Repeat alarm'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'once'), child: const Text('Once')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'daily'), child: const Text('Every day')),
          SimpleDialogOption(onPressed: () => Navigator.pop(dialogContext, 'custom'), child: const Text('Choose weekdays')),
        ],
      ),
    );
    if (repeat == null || !mounted) return;
    var weekdays = <int>[];
    if (repeat == 'custom') {
      final selected = <int>{};
      weekdays = await showDialog<List<int>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Choose weekdays'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: List<Widget>.generate(7, (index) {
                final day = index + 1;
                const labels = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(labels[index]),
                  value: selected.contains(day),
                  onChanged: (value) => setDialogState(() {
                    if (value == true) { selected.add(day); } else { selected.remove(day); }
                  }),
                );
              }),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, selected.toList()..sort()), child: const Text('Save')),
            ],
          ),
        ),
      ) ?? <int>[];
      if (weekdays.isEmpty || !mounted) return;
    }
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    final id = (DateTime.now().millisecondsSinceEpoch % 100000000).toInt();
    final alarm = <String, Object?>{
      'id': id,
      'title': title.isEmpty ? 'Snote alarm' : title,
      'at': at.toIso8601String(),
      'repeat': repeat,
      'weekdays': weekdays,
      'enabled': true,
      'silent': false,
    };
    try {
      await AlarmNotificationService.instance.schedule(
        id: id,
        title: alarm['title']! as String,
        firstAt: at,
        repeat: repeat,
        weekdays: weekdays,
      );
      if (!mounted) return;
      setState(() => _alarms.add(alarm));
      await _persistAlarms();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not schedule alarm: $error')),
      );
    }
  }

  Future<void> _toggleSavedAlarm(Map<String, Object?> alarm, bool enabled) async {
    final id = (alarm['id'] as num?)?.toInt();
    final at = DateTime.tryParse(alarm['at']?.toString() ?? '');
    if (id == null || at == null) return;
    try {
      if (enabled) {
        await AlarmNotificationService.instance.schedule(
          id: id,
          title: alarm['title']?.toString() ?? 'Snote alarm',
          firstAt: at,
          repeat: alarm['repeat']?.toString() ?? 'once',
          weekdays: (alarm['weekdays'] as List? ?? const <Object?>[]).whereType<num>().map((day) => day.toInt()).toList(),
          silent: alarm['silent'] == true,
        );
      } else {
        await AlarmNotificationService.instance.cancel(id);
      }
      setState(() => alarm['enabled'] = enabled);
      await _persistAlarms();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update alarm: $error')),
      );
    }
  }

  Future<void> _deleteSavedAlarm(Map<String, Object?> alarm) async {
    final id = (alarm['id'] as num?)?.toInt();
    if (id != null) await AlarmNotificationService.instance.cancel(id);
    if (!mounted) return;
    setState(() => _alarms.removeWhere((item) => item['id'] == alarm['id']));
    await _persistAlarms();
  }

  void _persistCollapsed(bool value) {
    unawaited(SnoteSettings.instance.setBool('floatingTimerCollapsed', value));
  }

  void _persistDockSide(String value) {
    unawaited(SnoteSettings.instance.setString('floatingTimerDockSide', value));
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    var timerCompleted = false;
    var alarmCompleted = false;
    setState(() {
      if (_timerRunning && _timerDeadline != null) {
        final left = _timerDeadline!.difference(now);
        if (left <= Duration.zero) {
          _timerRemaining = 0;
          _timerRunning = false;
          _timerDeadline = null;
          timerCompleted = true;
        } else {
          _timerRemaining = left.inSeconds +
              (left.inMilliseconds % 1000 == 0 ? 0 : 1);
        }
      }
      if (_alarmArmed &&
          _alarmDeadline != null &&
          !now.isBefore(_alarmDeadline!)) {
        _alarmArmed = false;
        _alarmDeadline = null;
        alarmCompleted = true;
      }
    });
    if (timerCompleted) _notify('Timer complete.');
    if (alarmCompleted) _notify('Alarm time reached.');
  }

  void _notify(String message) {
    if (SnoteSettings.instance.getBool('timerAlertEnabled')) {
      final sound = SnoteSettings.instance.getString('timerAlertSound');
      if (sound == 'click') {
        unawaited(SystemSound.play(SystemSoundType.click));
      } else if (sound == 'alert') {
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  String _format(Duration duration) {
    final total = math.max(0, duration.inSeconds);
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Duration get _stopwatchElapsed => _stopwatchAccumulated +
      (_stopwatchRunning && _stopwatchStartedAt != null
          ? DateTime.now().difference(_stopwatchStartedAt!)
          : Duration.zero);

  Future<void> _configureTimer() async {
    final controller = TextEditingController(text: _timerMinutes.toString());
    final minutes = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Timer settings'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Countdown duration',
            suffixText: 'minutes',
            helperText: 'Choose 1–240 minutes.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              if (value == null || value < 1 || value > 240) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || minutes == null) return;
    setState(() {
      _timerMinutes = minutes;
      if (!_timerRunning) _timerRemaining = minutes * 60;
    });
  }

  Future<void> _setAlarm() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _alarmTime ?? TimeOfDay.now(),
      helpText: 'Choose alarm time',
    );
    if (picked == null || !mounted) return;
    final now = DateTime.now();
    var deadline = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    if (!deadline.isAfter(now)) deadline = deadline.add(const Duration(days: 1));
    setState(() {
      _alarmTime = picked;
      _alarmDeadline = deadline;
      _alarmArmed = true;
    });
  }

  void _startOrPauseTimer() {
    setState(() {
      if (_timerRunning) {
        final remaining =
            _timerDeadline?.difference(DateTime.now()).inSeconds ?? 0;
        _timerRemaining = math.max(0, remaining).toInt();
        _timerRunning = false;
        _timerDeadline = null;
      } else {
        if (_timerRemaining <= 0) _timerRemaining = _timerMinutes * 60;
        _timerDeadline = DateTime.now().add(Duration(seconds: _timerRemaining));
        _timerRunning = true;
      }
    });
  }

  void _resetTimer() {
    setState(() {
      _timerRunning = false;
      _timerDeadline = null;
      _timerRemaining = _timerMinutes * 60;
    });
  }

  void _startOrPauseStopwatch() {
    setState(() {
      if (_stopwatchRunning) {
        _stopwatchAccumulated = _stopwatchElapsed;
        _stopwatchRunning = false;
        _stopwatchStartedAt = null;
      } else {
        _stopwatchStartedAt = DateTime.now();
        _stopwatchRunning = true;
      }
    });
  }

  void _resetStopwatch() {
    setState(() {
      _stopwatchAccumulated = Duration.zero;
      _stopwatchStartedAt = _stopwatchRunning ? DateTime.now() : null;
    });
  }

  void _dragPanel(DragUpdateDetails details, Size screen) {
    final width = math.min(330.0, screen.width - 16);
    setState(() {
      _offset = Offset(
        (_offset.dx + details.delta.dx)
            .clamp(0.0, math.max(0.0, screen.width - width))
            .toDouble(),
        (_offset.dy + details.delta.dy)
            .clamp(8.0, math.max(8.0, screen.height - 270))
            .toDouble(),
      );
    });
  }

  void _dockPanel(Size screen) {
    final width = math.min(330.0, screen.width - 16);
    if (_offset.dx <= 22) {
      setState(() {
        _dockSide = 'left';
        _collapsed = true;
        _offset = Offset(0, _offset.dy);
        _persistCollapsed(true);
        _persistDockSide('left');
      });
    } else if (_offset.dx + width >= screen.width - 22) {
      setState(() {
        _dockSide = 'right';
        _collapsed = true;
        _offset = Offset(screen.width - 28, _offset.dy);
        _persistCollapsed(true);
        _persistDockSide('right');
      });
    }
  }

  void _expand(Size screen) {
    final width = math.min(330.0, screen.width - 16);
    setState(() {
      _collapsed = false;
      _persistCollapsed(false);
      _offset = Offset(
        _dockSide == 'left' ? 8 : math.max(8.0, screen.width - width - 8),
        _offset.dy
            .clamp(8.0, math.max(8.0, screen.height - 270))
            .toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    if (_collapsed) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: _dockSide == 'left' ? 0 : null,
            right: _dockSide == 'right' ? 0 : null,
            top: _offset.dy
                .clamp(8.0, math.max(8.0, screen.height - 82))
                .toDouble(),
            child: GestureDetector(
              onTap: () => _expand(screen),
              onPanUpdate: (details) {
                setState(() {
                  _offset = Offset(
                    (_offset.dx + details.delta.dx)
                        .clamp(0.0, screen.width - 28)
                        .toDouble(),
                    (_offset.dy + details.delta.dy)
                        .clamp(8.0, math.max(8.0, screen.height - 82))
                        .toDouble(),
                  );
                  _dockSide =
                      _offset.dx < screen.width / 2 ? 'left' : 'right';
                  _persistDockSide(_dockSide);
                });
              },
              child: Material(
                elevation: 6,
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(_dockSide == 'left' ? 0 : 14),
                  right: Radius.circular(_dockSide == 'right' ? 0 : 14),
                ),
                child: const SizedBox(
                  width: 30,
                  height: 76,
                  child: Tooltip(
                    message: 'Expand timer, alarm and stopwatch',
                    child: Icon(Icons.timer_rounded),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final panelWidth = math.min(330.0, screen.width - 16);
    final left = _offset.dx
        .clamp(8.0, math.max(8.0, screen.width - panelWidth - 8))
        .toDouble();
    final top = _offset.dy
        .clamp(8.0, math.max(8.0, screen.height - 270))
        .toDouble();
    final display = switch (_mode) {
      'stopwatch' => _format(_stopwatchElapsed),
      'alarm' => _alarmArmed && _alarmDeadline != null
          ? 'Alarm ${TimeOfDay.fromDateTime(_alarmDeadline!).format(context)}'
          : _alarmTime == null
              ? 'No alarm set'
              : 'Alarm ${_alarmTime!.format(context)}',
      _ => _format(Duration(seconds: _timerRemaining)),
    };

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          top: top,
          child: Material(
            elevation: 10,
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: panelWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onPanUpdate: (details) => _dragPanel(details, screen),
                    onPanEnd: (_) => _dockPanel(screen),
                    child: Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Timer & stopwatch',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'Alert settings',
                            icon: const Icon(Icons.notifications_active_outlined, size: 18),
                            onSelected: (value) async {
                              if (value == 'enabled') {
                                await SnoteSettings.instance.setBool('timerAlertEnabled', !SnoteSettings.instance.getBool('timerAlertEnabled'));
                              } else {
                                await SnoteSettings.instance.setString('timerAlertSound', value);
                              }
                              if (mounted) setState(() {});
                            },
                            itemBuilder: (_) => [
                              CheckedPopupMenuItem<String>(
                                value: 'enabled',
                                checked: SnoteSettings.instance.getBool('timerAlertEnabled'),
                                child: const Text('Sound alerts enabled'),
                              ),
                              CheckedPopupMenuItem<String>(
                                value: 'alert',
                                checked: SnoteSettings.instance.getString('timerAlertSound') == 'alert',
                                child: const Text('Alert sound'),
                              ),
                              CheckedPopupMenuItem<String>(
                                value: 'click',
                                checked: SnoteSettings.instance.getString('timerAlertSound') == 'click',
                                child: const Text('Click sound'),
                              ),
                              CheckedPopupMenuItem<String>(
                                value: 'none',
                                checked: SnoteSettings.instance.getString('timerAlertSound') == 'none',
                                child: const Text('Silent'),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Collapse to screen edge',
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final side = left + panelWidth / 2 < screen.width / 2
                                  ? 'left'
                                  : 'right';
                              setState(() {
                                _dockSide = side;
                                _collapsed = true;
                                _offset = Offset(
                                  side == 'left' ? 0 : screen.width - 28,
                                  top,
                                );
                              });
                            },
                            icon: const Icon(Icons.chevron_right_rounded, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Close timer panel',
                            visualDensity: VisualDensity.compact,
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(
                      children: [
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 'timer', label: Text('Timer')),
                            ButtonSegment(value: 'stopwatch', label: Text('Stopwatch')),
                            ButtonSegment(value: 'alarm', label: Text('Alarm')),
                          ],
                          selected: <String>{_mode},
                          onSelectionChanged: (selection) =>
                              setState(() => _mode = selection.first),
                        ),
                        const SizedBox(height: 12),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            display,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_mode == 'timer')
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _startOrPauseTimer,
                                icon: Icon(_timerRunning
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded),
                                label: Text(_timerRunning ? 'Pause' : 'Start'),
                              ),
                              IconButton(
                                tooltip: 'Reset timer',
                                onPressed: _resetTimer,
                                icon: const Icon(Icons.restart_alt_rounded),
                              ),
                              IconButton(
                                tooltip: 'Timer settings',
                                onPressed: _configureTimer,
                                icon: const Icon(Icons.settings_outlined),
                              ),
                            ],
                          )
                        else if (_mode == 'stopwatch')
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                onPressed: _startOrPauseStopwatch,
                                icon: Icon(_stopwatchRunning
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded),
                                label: Text(_stopwatchRunning ? 'Pause' : 'Start'),
                              ),
                              IconButton(
                                tooltip: 'Reset stopwatch',
                                onPressed: _resetStopwatch,
                                icon: const Icon(Icons.restart_alt_rounded),
                              ),
                            ],
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.center,
                                child: FilledButton.tonalIcon(
                                  onPressed: _addSavedAlarm,
                                  icon: const Icon(Icons.alarm_add_rounded),
                                  label: const Text('Add alarm'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_alarms.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Text('No saved alarms yet.', textAlign: TextAlign.center),
                                ),
                              ..._alarms.map((alarm) {
                                final at = DateTime.tryParse(alarm['at']?.toString() ?? '');
                                final time = at == null ? '--:--' : TimeOfDay.fromDateTime(at).format(context);
                                final repeat = alarm['repeat'] == 'daily'
                                    ? 'Daily'
                                    : alarm['repeat'] == 'custom'
                                        ? 'Custom weekdays'
                                        : 'Once';
                                return ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.alarm_rounded),
                                  title: Text(alarm['title']?.toString() ?? 'Alarm'),
                                  subtitle: Text('$time · $repeat'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Switch(
                                        value: alarm['enabled'] == true,
                                        onChanged: (value) => _toggleSavedAlarm(alarm, value),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete alarm',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _deleteSavedAlarm(alarm),
                                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const Divider(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _setAlarm,
                                  icon: const Icon(Icons.alarm_on_rounded, size: 18),
                                  label: const Text('Quick one-time alarm'),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
