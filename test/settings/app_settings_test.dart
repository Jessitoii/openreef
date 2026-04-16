import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/settings/app_settings.dart';

void main() {
  test('supports trigger mail polling minutes in json and writes', () {
    const settings = AppSettings(triggerMailPollMinutes: 12);

    expect(settings.readValue('trigger.mailPollMinutes'), 12);
    expect(settings.toJson()['trigger.mailPollMinutes'], 12);

    final updated = settings.writeValue('trigger.mailPollMinutes', 18);
    expect(updated.triggerMailPollMinutes, 18);
  });

  test('persists generation model id outside LLM writable settings', () {
    const settings = AppSettings(generationModelId: 'gemma-4-e2b-it');

    expect(settings.toJson()['generation.modelId'], 'gemma-4-e2b-it');

    final rehydrated = AppSettings.fromJson(settings.toJson());
    expect(rehydrated.generationModelId, 'gemma-4-e2b-it');
    expect(
      () => rehydrated.readValue('generation.modelId'),
      throwsArgumentError,
    );
  });
}
