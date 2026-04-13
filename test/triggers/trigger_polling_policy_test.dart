import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_polling_policy.dart';
import 'dart:io';

void main() {
  late Directory tempDir;
  late File settingsFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openreef_polling_policy');
    settingsFile = File('${tempDir.path}${Platform.pathSeparator}settings.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('resolves trigger override before global setting and default', () async {
    final controller = SettingsController(store: SettingsStore(settingsFile));
    await controller.initialize();
    await controller.writeToolValue('trigger.mailPollMinutes', 25);

    const trigger = TriggerConfig(
      id: 'mail_check',
      name: 'Mail check',
      prompt: 'Check mail.',
      type: TriggerType.interval,
      priority: TriggerPriority.normal,
      intervalSpec: IntervalTriggerSpec(every: Duration(minutes: 10)),
      pollIntervalMinutes: 7,
    );

    final policy = TriggerPollingPolicy();
    expect(policy.resolvePollMinutes(trigger, controller), 7);

    final withoutOverride = trigger.copyWith(clearIntervalSpec: false, pollIntervalMinutes: null);
    expect(policy.resolvePollMinutes(withoutOverride, controller), 25);
  });

  test('rejects intervals under fifteen minutes for Android app-closed polling', () {
    const policy = TriggerPollingPolicy();
    expect(
      policy.validateResolvedMinutes(4).isValid,
      isFalse,
    );
    expect(policy.validateResolvedMinutes(10).isValid, isFalse);
    expect(policy.validateResolvedMinutes(15).isValid, isTrue);
  });
}
