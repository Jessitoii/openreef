enum ReefThemeMode { dark, light, system }

enum VoiceTtsEngine { android, kokoro }

class AppSettings {
  const AppSettings({
    this.themeMode = ReefThemeMode.dark,
    this.voiceTtsEngine = VoiceTtsEngine.android,
    this.wakeWordEnabled = false,
    this.voiceSensitivity = 0.7,
    this.triggerMailPollMinutes = 15,
    this.semanticEmbeddingModelId,
  });

  static const Set<String> llmWritableKeys = <String>{
    'theme.mode',
    'voice.ttsEngine',
    'voice.wakeWordEnabled',
    'voice.sensitivity',
    'trigger.mailPollMinutes',
  };

  final ReefThemeMode themeMode;
  final VoiceTtsEngine voiceTtsEngine;
  final bool wakeWordEnabled;
  final double voiceSensitivity;
  final int triggerMailPollMinutes;
  final String? semanticEmbeddingModelId;

  AppSettings copyWith({
    ReefThemeMode? themeMode,
    VoiceTtsEngine? voiceTtsEngine,
    bool? wakeWordEnabled,
    double? voiceSensitivity,
    int? triggerMailPollMinutes,
    String? semanticEmbeddingModelId,
    bool clearSemanticEmbeddingModelId = false,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      voiceTtsEngine: voiceTtsEngine ?? this.voiceTtsEngine,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      voiceSensitivity: voiceSensitivity ?? this.voiceSensitivity,
      triggerMailPollMinutes:
          triggerMailPollMinutes ?? this.triggerMailPollMinutes,
      semanticEmbeddingModelId: clearSemanticEmbeddingModelId
          ? null
          : (semanticEmbeddingModelId ?? this.semanticEmbeddingModelId),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'theme.mode': themeMode.name,
      'voice.ttsEngine': voiceTtsEngine.name,
      'voice.wakeWordEnabled': wakeWordEnabled,
      'voice.sensitivity': voiceSensitivity,
      'trigger.mailPollMinutes': triggerMailPollMinutes,
      if (semanticEmbeddingModelId != null)
        'semantic.embeddingModelId': semanticEmbeddingModelId,
    };
  }

  Map<String, Object?> toToolMap() => toJson();

  factory AppSettings.fromJson(Map<String, Object?> json) {
    return AppSettings(
      themeMode: _parseThemeMode(json['theme.mode'] as String?),
      voiceTtsEngine: _parseTtsEngine(json['voice.ttsEngine'] as String?),
      wakeWordEnabled: json['voice.wakeWordEnabled'] as bool? ?? false,
      voiceSensitivity: _clampSensitivity(
        (json['voice.sensitivity'] as num?)?.toDouble() ?? 0.7,
      ),
      triggerMailPollMinutes:
          (json['trigger.mailPollMinutes'] as num?)?.toInt() ?? 15,
      semanticEmbeddingModelId: json['semantic.embeddingModelId'] as String?,
    );
  }

  Object? readValue(String key) {
    return switch (key) {
      'theme.mode' => themeMode.name,
      'voice.ttsEngine' => voiceTtsEngine.name,
      'voice.wakeWordEnabled' => wakeWordEnabled,
      'voice.sensitivity' => voiceSensitivity,
      'trigger.mailPollMinutes' => triggerMailPollMinutes,
      _ => throw ArgumentError.value(key, 'key', 'unsupported_setting_key'),
    };
  }

  AppSettings writeValue(String key, Object? value) {
    return switch (key) {
      'theme.mode' => copyWith(themeMode: _parseThemeModeValue(value)),
      'voice.ttsEngine' => copyWith(
        voiceTtsEngine: _parseTtsEngineValue(value),
      ),
      'voice.wakeWordEnabled' => copyWith(
        wakeWordEnabled: _parseBoolValue(value, key),
      ),
      'voice.sensitivity' => copyWith(
        voiceSensitivity: _clampSensitivity(_parseDoubleValue(value, key)),
      ),
      'trigger.mailPollMinutes' => copyWith(
        triggerMailPollMinutes: _parseIntValue(value, key),
      ),
      _ => throw ArgumentError.value(key, 'key', 'unsupported_setting_key'),
    };
  }

  static ReefThemeMode _parseThemeMode(String? value) {
    return ReefThemeMode.values
            .where((mode) => mode.name == value)
            .firstOrNull ??
        ReefThemeMode.dark;
  }

  static VoiceTtsEngine _parseTtsEngine(String? value) {
    return VoiceTtsEngine.values
            .where((engine) => engine.name == value)
            .firstOrNull ??
        VoiceTtsEngine.android;
  }

  static ReefThemeMode _parseThemeModeValue(Object? value) {
    if (value is! String) {
      throw ArgumentError.value(value, 'value', 'invalid_theme_mode');
    }
    final mode = ReefThemeMode.values
        .where((item) => item.name == value)
        .firstOrNull;
    if (mode == null) {
      throw ArgumentError.value(value, 'value', 'invalid_theme_mode');
    }
    return mode;
  }

  static VoiceTtsEngine _parseTtsEngineValue(Object? value) {
    if (value is! String) {
      throw ArgumentError.value(value, 'value', 'invalid_tts_engine');
    }
    final engine = VoiceTtsEngine.values
        .where((item) => item.name == value)
        .firstOrNull;
    if (engine == null) {
      throw ArgumentError.value(value, 'value', 'invalid_tts_engine');
    }
    return engine;
  }

  static bool _parseBoolValue(Object? value, String key) {
    if (value is! bool) {
      throw ArgumentError.value(value, key, 'invalid_bool_value');
    }
    return value;
  }

  static double _parseDoubleValue(Object? value, String key) {
    if (value is num) {
      return value.toDouble();
    }
    throw ArgumentError.value(value, key, 'invalid_double_value');
  }

  static int _parseIntValue(Object? value, String key) {
    if (value is num) {
      return value.toInt();
    }
    throw ArgumentError.value(value, key, 'invalid_int_value');
  }

  static double _clampSensitivity(double value) => value.clamp(0.3, 0.9);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
