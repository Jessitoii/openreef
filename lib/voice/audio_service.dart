import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:openreef/settings/app_settings.dart';
import 'package:openreef/settings/settings_controller.dart';

abstract class VoiceTtsClient {
  Future<void> awaitSpeakCompletion(bool enabled);

  Future<void> speak(String text);

  Future<void> stop();
}

class FlutterVoiceTtsClient implements VoiceTtsClient {
  FlutterVoiceTtsClient({FlutterTts? flutterTts})
    : _flutterTts = flutterTts ?? FlutterTts();

  final FlutterTts _flutterTts;

  @override
  Future<void> awaitSpeakCompletion(bool enabled) async {
    await _flutterTts.awaitSpeakCompletion(enabled);
  }

  @override
  Future<void> speak(String text) async {
    await _flutterTts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _flutterTts.stop();
  }
}

/// Owns text-to-speech playback and keeps it aligned with the live settings
/// state instead of letting UI widgets decide when audio is allowed.
class AudioService extends ChangeNotifier {
  AudioService({
    required SettingsController settingsController,
    VoiceTtsClient? ttsClient,
    bool? isSupportedOverride,
  }) : _settingsController = settingsController,
       _ttsClient = ttsClient ?? FlutterVoiceTtsClient(),
       _isSupportedOverride = isSupportedOverride {
    _settingsController.addListener(_handleSettingsChanged);
    _configuration = _configure();
  }

  final SettingsController _settingsController;
  final VoiceTtsClient _ttsClient;
  final bool? _isSupportedOverride;

  late final Future<void> _configuration;
  bool _disposed = false;
  bool _speaking = false;

  bool get isSupported =>
      _isSupportedOverride ??
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  bool get isEnabled =>
      isSupported &&
      _settingsController.settings.wakeWordEnabled &&
      _settingsController.settings.voiceTtsEngine == VoiceTtsEngine.android;

  bool get isSpeaking => _speaking;

  Future<bool> speak(String text) async {
    if (!isEnabled || text.trim().isEmpty) {
      return false;
    }

    await _configuration;
    _setSpeaking(true);
    try {
      await _ttsClient.speak(text);
      return true;
    } finally {
      _setSpeaking(false);
    }
  }

  Future<void> stop() async {
    await _ttsClient.stop();
    _setSpeaking(false);
  }

  @override
  void dispose() {
    _disposed = true;
    _settingsController.removeListener(_handleSettingsChanged);
    unawaited(_ttsClient.stop());
    super.dispose();
  }

  Future<void> _configure() async {
    await _ttsClient.awaitSpeakCompletion(true);
  }

  void _handleSettingsChanged() {
    if (!isEnabled) {
      unawaited(stop());
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _setSpeaking(bool value) {
    if (_speaking == value || _disposed) {
      return;
    }
    _speaking = value;
    notifyListeners();
  }
}
