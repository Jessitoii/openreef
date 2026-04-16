import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:openreef/settings/app_settings.dart';
import 'package:openreef/settings/settings_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({required SettingsStore store}) : _store = store;

  final SettingsStore _store;
  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  Future<void> initialize() async {
    _settings = await _store.read();
  }

  Map<String, Object?> readAllToolValues() => _settings.toToolMap();

  Object? readToolValue(String key) => _settings.readValue(key);

  Future<void> writeToolValue(String key, Object? value) async {
    if (!AppSettings.llmWritableKeys.contains(key)) {
      throw ArgumentError.value(key, 'key', 'setting_not_llm_writable');
    }
    final nextSettings = _settings.writeValue(key, value);
    _settings = nextSettings;
    notifyListeners();
    await _store.write(_settings);
  }

  void updateThemeMode(ReefThemeMode mode) {
    _update(_settings.copyWith(themeMode: mode));
  }

  void updateVoiceTtsEngine(VoiceTtsEngine engine) {
    _update(_settings.copyWith(voiceTtsEngine: engine));
  }

  void updateWakeWordEnabled(bool enabled) {
    _update(_settings.copyWith(wakeWordEnabled: enabled));
  }

  void updateVoiceSensitivity(double sensitivity) {
    _update(_settings.copyWith(voiceSensitivity: sensitivity.clamp(0.3, 0.9)));
  }

  void updateSemanticEmbeddingModelId(String modelId) {
    _update(_settings.copyWith(semanticEmbeddingModelId: modelId));
  }

  void updateGenerationModelId(String modelId) {
    _update(_settings.copyWith(generationModelId: modelId));
  }

  void _update(AppSettings nextSettings) {
    _settings = nextSettings;
    notifyListeners();
    unawaited(_store.write(_settings));
  }
}
