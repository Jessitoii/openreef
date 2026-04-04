import 'package:flutter/foundation.dart';
import 'package:openreef/settings/app_settings.dart';

class SettingsController extends ChangeNotifier {
  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

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
    _update(
      _settings.copyWith(
        voiceSensitivity: sensitivity.clamp(0.3, 0.9),
      ),
    );
  }

  void _update(AppSettings nextSettings) {
    _settings = nextSettings;
    notifyListeners();
  }
}
