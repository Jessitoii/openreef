import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/triggers/trigger_codec.dart';
import 'package:openreef/triggers/trigger_models.dart';

void main() {
  test('preserves trigger polling interval fields', () {
    const trigger = TriggerConfig(
      id: 'mail_watch',
      name: 'Mail watch',
      prompt: 'Check mail every 20 minutes.',
      type: TriggerType.interval,
      priority: TriggerPriority.normal,
      intervalSpec: IntervalTriggerSpec(every: Duration(minutes: 20)),
      pollIntervalMinutes: 20,
    );

    const codec = TriggerCodec();
    final encoded = codec.encode(trigger);
    final decoded = codec.decode(encoded);

    expect(encoded['pollIntervalMinutes'], 20);
    expect(decoded.pollIntervalMinutes, 20);
    expect(decoded.intervalSpec?.every.inMinutes, 20);
  });
}
