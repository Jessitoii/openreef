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
}
