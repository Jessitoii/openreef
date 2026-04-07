import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openreef/settings/settings_controller.dart';

enum WakeWordEventType { detected }

class WakeWordEvent {
  const WakeWordEvent({required this.type, required this.detectedAt});

  factory WakeWordEvent.detected() {
    return WakeWordEvent(
      type: WakeWordEventType.detected,
      detectedAt: DateTime.now(),
    );
  }

  final WakeWordEventType type;
  final DateTime detectedAt;
}

/// Controls the Android wake-word foreground service and listens to native
/// wake-word detections emitted over the Flutter event channel.
class WakeWordController extends ChangeNotifier {
  WakeWordController({
    required SettingsController settingsController,
    OptionalMethodChannel? methodChannel,
    EventChannel? eventChannel,
    Stream<dynamic>? eventStream,
    bool? isSupportedOverride,
  }) : _settingsController = settingsController,
       _methodChannel =
           methodChannel ?? const OptionalMethodChannel(methodChannelName),
       _eventChannel = eventChannel ?? const EventChannel(eventChannelName),
       _eventStreamOverride = eventStream,
       _isSupportedOverride = isSupportedOverride {
    _settingsController.addListener(_handleSettingsChanged);
    _eventSubscription = _platformEvents().listen(_handlePlatformEvent);
    unawaited(_initializeWakeRuntime());
  }

  static const String methodChannelName = 'openreef/wake_word_channel';
  static const String eventChannelName = 'openreef/wake_word_events';

  static const String _startMethod = 'startListening';
  static const String _stopMethod = 'stopListening';
  static const String _statusMethod = 'isListening';
  static const String _availabilityMethod = 'isAvailable';
  static const String _setSensitivityMethod = 'setSensitivity';

  final SettingsController _settingsController;
  final OptionalMethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final Stream<dynamic>? _eventStreamOverride;
  final bool? _isSupportedOverride;
  final StreamController<WakeWordEvent> _events =
      StreamController<WakeWordEvent>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  DateTime? _lastDetectedAt;
  bool _isAvailable = false;
  bool _isListening = false;

  bool get isSupported =>
      _isSupportedOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  bool get isAvailable => isSupported && _isAvailable;
  bool get isListening => _isListening;

  DateTime? get lastDetectedAt => _lastDetectedAt;

  Stream<WakeWordEvent> get events => _events.stream;

  Future<bool> startListening() async {
    if (!await refreshAvailability()) {
      _setListening(false);
      return false;
    }

    await updateSensitivity(_settingsController.settings.voiceSensitivity);
    final started = await _methodChannel.invokeMethod<bool>(_startMethod);
    _setListening(started ?? false);
    return _isListening;
  }

  Future<bool> stopListening() async {
    if (!isSupported) {
      _setAvailable(false);
      _setListening(false);
      return false;
    }

    final stopped = await _methodChannel.invokeMethod<bool>(_stopMethod);
    _setListening(!(stopped ?? false) ? _isListening : false);
    return stopped ?? false;
  }

  Future<bool> refreshListeningState() async {
    if (!isSupported) {
      _setAvailable(false);
      _setListening(false);
      return false;
    }

    final listening = await _methodChannel.invokeMethod<bool>(_statusMethod);
    _setListening(listening ?? false);
    return _isListening;
  }

  Future<bool> refreshAvailability() async {
    if (!isSupported) {
      _setAvailable(false);
      _setListening(false);
      return false;
    }

    final available = await _methodChannel.invokeMethod<bool>(
      _availabilityMethod,
    );
    _setAvailable(available ?? false);
    if (!_isAvailable) {
      _setListening(false);
    }
    return _isAvailable;
  }

  Future<void> updateSensitivity(double sensitivity) async {
    if (!await refreshAvailability()) {
      return;
    }

    await _methodChannel.invokeMethod<void>(
      _setSensitivityMethod,
      <String, Object?>{'value': sensitivity.clamp(0.3, 0.9)},
    );
  }

  Future<void> syncWithSettings() async {
    final available = await refreshAvailability();
    if (!available) {
      return;
    }

    await updateSensitivity(_settingsController.settings.voiceSensitivity);
    if (!_settingsController.settings.wakeWordEnabled) {
      await stopListening();
      return;
    }

    await startListening();
  }

  @override
  void dispose() {
    _settingsController.removeListener(_handleSettingsChanged);
    _eventSubscription?.cancel();
    _events.close();
    super.dispose();
  }

  void _handleSettingsChanged() {
    unawaited(syncWithSettings());
  }

  Future<void> _initializeWakeRuntime() async {
    await refreshAvailability();
    await syncWithSettings();
  }

  Stream<dynamic> _platformEvents() {
    if (!isSupported) {
      return const Stream<dynamic>.empty();
    }
    return _eventStreamOverride ?? _eventChannel.receiveBroadcastStream();
  }

  void _handlePlatformEvent(dynamic payload) {
    final eventName = switch (payload) {
      String value => value,
      Map<dynamic, dynamic> value => value['event']?.toString(),
      _ => null,
    };

    if (eventName != 'detected') {
      return;
    }

    final event = WakeWordEvent.detected();
    _lastDetectedAt = event.detectedAt;
    _events.add(event);
    notifyListeners();
  }

  void _setListening(bool value) {
    if (_isListening == value) {
      return;
    }
    _isListening = value;
    notifyListeners();
  }

  void _setAvailable(bool value) {
    if (_isAvailable == value) {
      return;
    }
    _isAvailable = value;
    notifyListeners();
  }
}
