import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openreef_settings_test');
    settingsFile = File(
      '${tempDir.path}${Platform.pathSeparator}settings.json',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('writes a whitelisted setting and rehydrates it from disk', () async {
    final controller = SettingsController(store: SettingsStore(settingsFile));
    await controller.initialize();

    await controller.writeToolValue('theme.mode', 'light');

    final rehydrated = SettingsController(store: SettingsStore(settingsFile));
    await rehydrated.initialize();

    expect(controller.readToolValue('theme.mode'), 'light');
    expect(rehydrated.readToolValue('theme.mode'), 'light');
  });

  test('rejects non-whitelisted setting keys', () async {
    final controller = SettingsController(store: SettingsStore(settingsFile));
    await controller.initialize();

    expect(
      controller.writeToolValue('privacy.biometricLock', true),
      throwsArgumentError,
    );
  });

  test('persists trigger mail polling minutes', () async {
    final controller = SettingsController(store: SettingsStore(settingsFile));
    await controller.initialize();

    await controller.writeToolValue('trigger.mailPollMinutes', 18);

    final rehydrated = SettingsController(store: SettingsStore(settingsFile));
    await rehydrated.initialize();

    expect(rehydrated.settings.triggerMailPollMinutes, 18);
    expect(rehydrated.readToolValue('trigger.mailPollMinutes'), 18);
  });

  test(
    'persists semantic embedding model selection outside LLM writes',
    () async {
      final controller = SettingsController(store: SettingsStore(settingsFile));
      await controller.initialize();

      controller.updateSemanticEmbeddingModelId('gecko-512');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final rehydrated = SettingsController(store: SettingsStore(settingsFile));
      await rehydrated.initialize();

      expect(rehydrated.settings.semanticEmbeddingModelId, 'gecko-512');
      expect(
        () => rehydrated.readToolValue('semantic.embeddingModelId'),
        throwsArgumentError,
      );
    },
  );

  test('persists generation model selection outside LLM writes', () async {
    final controller = SettingsController(store: SettingsStore(settingsFile));
    await controller.initialize();

    controller.updateGenerationModelId('function-gemma-270m-it');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final rehydrated = SettingsController(store: SettingsStore(settingsFile));
    await rehydrated.initialize();

    expect(rehydrated.settings.generationModelId, 'function-gemma-270m-it');
    expect(
      () => rehydrated.readToolValue('generation.modelId'),
      throwsArgumentError,
    );
  });
}
