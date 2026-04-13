import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/triggers/trigger_platform_event.dart';

void main() {
  test('parses delivery stage and delivery id from native payloads', () {
    final event = TriggerPlatformEvent.fromPlatformPayload(
      <String, Object?>{
        'triggerId': 'interval_sync',
        'deliveryId': 'interval_sync_123',
        'type': 'interval',
        'scheduledAtEpochMs': 123,
        'deliveredAtEpochMs': 456,
        'deliveryStage': 'handed_off_to_flutter',
        'payload': <String, Object?>{'kind': 'poll'},
      },
    );

    expect(event.deliveryId, 'interval_sync_123');
    expect(event.deliveryStage, 'handed_off_to_flutter');
    expect(event.payload['kind'], 'poll');
  });
}
