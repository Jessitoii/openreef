import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/triggers/android_schedule_scheduler_backend.dart';
import 'package:openreef/triggers/trigger_channels.dart';
import 'package:openreef/triggers/trigger_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = OptionalMethodChannel(triggerMethodChannelName);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (call) async {
          calls.add(call);
          if (call.method == AndroidScheduleSchedulerBackend.permissionMethod) {
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  test('serializes exact schedule registration for Android', () async {
    final backend = AndroidScheduleSchedulerBackend(
      methodChannel: methodChannel,
    );

    await backend.registerSchedule(
      const TriggerConfig(
        id: 'briefing',
        name: 'Morning briefing',
        prompt: 'Deliver morning briefing.',
        type: TriggerType.schedule,
        priority: TriggerPriority.high,
        scheduleSpec: ScheduleTriggerSpec(hour: 8, minute: 15),
        payload: <String, Object?>{'source': 'daily_digest', 'count': 3},
        requiresUserAttention: true,
        isExpensive: true,
      ),
    );

    expect(calls, hasLength(2));
    expect(calls[0].method, AndroidScheduleSchedulerBackend.permissionMethod);
    expect(calls[1].method, AndroidScheduleSchedulerBackend.registerMethod);
    expect(calls[1].arguments, <String, Object?>{
      'triggerId': 'briefing',
      'name': 'Morning briefing',
      'type': 'schedule',
      'priority': 'high',
      'hour': 8,
      'minute': 15,
      'payload': <String, Object?>{'source': 'daily_digest', 'count': 3},
      'requiresUserAttention': true,
      'isExpensive': true,
    });
  });

  test('reports unsupported platforms as disabled', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final backend = AndroidScheduleSchedulerBackend(
      methodChannel: methodChannel,
      isSupportedOverride: false,
    );

    await backend.registerSchedule(
      const TriggerConfig(
        id: 'ignored',
        name: 'Ignored',
        prompt: 'Ignored schedule.',
        type: TriggerType.schedule,
        priority: TriggerPriority.low,
        scheduleSpec: ScheduleTriggerSpec(hour: 6, minute: 0),
      ),
    );

    expect(await backend.hasExactAlarmPermission(), isFalse);
    expect(calls, isEmpty);
  });

  test('serializes cron registration for Android', () async {
    final backend = AndroidScheduleSchedulerBackend(
      methodChannel: methodChannel,
    );

    await backend.registerSchedule(
      const TriggerConfig(
        id: 'weekday_digest',
        name: 'Weekday digest',
        prompt: 'Deliver weekday digest.',
        type: TriggerType.cron,
        priority: TriggerPriority.normal,
        cronSpec: CronTriggerSpec(expression: '0 9 * * 1-5'),
      ),
    );

    expect(calls[1].arguments, <String, Object?>{
      'triggerId': 'weekday_digest',
      'name': 'Weekday digest',
      'type': 'cron',
      'priority': 'normal',
      'cronExpression': '0 9 * * 1-5',
      'payload': <String, Object?>{},
      'requiresUserAttention': false,
      'isExpensive': false,
    });
  });
}
