import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/settings/app_settings.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/voice/audio_service.dart';

void main() {
  test('audio service speaks when Android TTS is enabled in settings', () async {
    final settingsController = SettingsController();
    final ttsClient = _FakeVoiceTtsClient();
    final service = AudioService(
      settingsController: settingsController,
      ttsClient: ttsClient,
      isSupportedOverride: true,
    );
    addTearDown(service.dispose);

    settingsController.updateWakeWordEnabled(true);

    expect(await service.speak('OpenReef online'), isTrue);
    expect(ttsClient.spokenTexts, <String>['OpenReef online']);
  });

  test('audio service stays disabled when wake word is off', () async {
    final settingsController = SettingsController();
    final ttsClient = _FakeVoiceTtsClient();
    final service = AudioService(
      settingsController: settingsController,
      ttsClient: ttsClient,
      isSupportedOverride: true,
    );
    addTearDown(service.dispose);

    expect(await service.speak('Muted'), isFalse);
    expect(ttsClient.spokenTexts, isEmpty);
  });

  test('audio service stays disabled for unsupported TTS engines', () async {
    final settingsController = SettingsController();
    final ttsClient = _FakeVoiceTtsClient();
    final service = AudioService(
      settingsController: settingsController,
      ttsClient: ttsClient,
      isSupportedOverride: true,
    );
    addTearDown(service.dispose);

    settingsController.updateWakeWordEnabled(true);
    settingsController.updateVoiceTtsEngine(VoiceTtsEngine.kokoro);

    expect(await service.speak('Use Kokoro later'), isFalse);
    expect(ttsClient.spokenTexts, isEmpty);
  });

  test('audio service stops playback when settings disable voice output', () async {
    final settingsController = SettingsController();
    final ttsClient = _FakeVoiceTtsClient();
    final service = AudioService(
      settingsController: settingsController,
      ttsClient: ttsClient,
      isSupportedOverride: true,
    );
    addTearDown(service.dispose);

    settingsController.updateWakeWordEnabled(true);
    await service.speak('Before disable');

    settingsController.updateWakeWordEnabled(false);
    await Future<void>.delayed(Duration.zero);

    expect(ttsClient.stopCalls, greaterThanOrEqualTo(1));
  });
}

class _FakeVoiceTtsClient implements VoiceTtsClient {
  final List<String> spokenTexts = <String>[];
  int stopCalls = 0;
  bool awaitSpeakCompletionEnabled = false;

  @override
  Future<void> awaitSpeakCompletion(bool enabled) async {
    awaitSpeakCompletionEnabled = enabled;
  }

  @override
  Future<void> speak(String text) async {
    spokenTexts.add(text);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}
