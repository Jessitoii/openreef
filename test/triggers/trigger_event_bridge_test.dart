import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/triggers/trigger_event_bridge.dart';
import 'package:openreef/triggers/trigger_platform_event.dart';

void main() {
  test('parses native schedule event payloads', () async {
    final bridge = TriggerEventBridge(
      eventStream: Stream<dynamic>.value(<String, Object?>{
        'triggerId': 'briefing',
        'type': 'schedule',
        'scheduledAtEpochMs': 1_710_000_000_000,
        'deliveredAtEpochMs': 1_710_000_005_000,
        'enqueuedAtEpochMs': 1_710_000_004_000,
        'payload': <String, Object?>{'origin': 'alarm_manager', 'attempt': 1},
      }),
      isSupportedOverride: true,
    );
    addTearDown(bridge.dispose);

    final event = await bridge.events.first;

    expect(
      event,
      isA<TriggerPlatformEvent>()
          .having((value) => value.triggerId, 'triggerId', 'briefing')
          .having((value) => value.type, 'type', 'schedule')
          .having(
            (value) => value.scheduledAtEpochMs,
            'scheduledAtEpochMs',
            1_710_000_000_000,
          )
          .having(
            (value) => value.deliveredAtEpochMs,
            'deliveredAtEpochMs',
            1_710_000_005_000,
          )
          .having(
            (value) => value.enqueuedAtEpochMs,
            'enqueuedAtEpochMs',
            1_710_000_004_000,
          )
          .having((value) => value.payload, 'payload', <String, Object?>{
            'origin': 'alarm_manager',
            'attempt': 1,
          }),
    );
    expect(bridge.lastEvent?.triggerId, 'briefing');
  });

  test('ignores event subscriptions on unsupported platforms', () async {
    final controller = StreamController<dynamic>.broadcast();
    final bridge = TriggerEventBridge(
      eventStream: controller.stream,
      isSupportedOverride: false,
    );
    addTearDown(() async {
      await controller.close();
      bridge.dispose();
    });

    controller.add(<String, Object?>{
      'triggerId': 'ignored',
      'type': 'schedule',
      'scheduledAtEpochMs': 1,
      'deliveredAtEpochMs': 2,
      'payload': const <String, Object?>{},
    });
    await Future<void>.delayed(Duration.zero);

    expect(bridge.lastEvent, isNull);
  });
}
