enum ReefThemeMode { dark, light, system }

enum VoiceTtsEngine { android, kokoro }

class AppSettings {
  const AppSettings({
    this.themeMode = ReefThemeMode.dark,
    this.voiceTtsEngine = VoiceTtsEngine.android,
    this.wakeWordEnabled = false,
    this.voiceSensitivity = 0.7,
  });

  final ReefThemeMode themeMode;
  final VoiceTtsEngine voiceTtsEngine;
  final bool wakeWordEnabled;
  final double voiceSensitivity;

  AppSettings copyWith({
    ReefThemeMode? themeMode,
    VoiceTtsEngine? voiceTtsEngine,
    bool? wakeWordEnabled,
    double? voiceSensitivity,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      voiceTtsEngine: voiceTtsEngine ?? this.voiceTtsEngine,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      voiceSensitivity: voiceSensitivity ?? this.voiceSensitivity,
    );
  }
}
