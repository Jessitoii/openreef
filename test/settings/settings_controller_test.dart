import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';

void main() {
  late Directory tempDir;
  late File settingsFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openreef_settings_test');
    settingsFile = File('${tempDir.path}${Platform.pathSeparator}settings.json');
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
}
