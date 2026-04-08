import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_repository.dart';

void main() {
  late Directory tempDir;
  late TriggerRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('openreef_trigger_repo');
    repository = TriggerRepository(
      file: File('${tempDir.path}${Platform.pathSeparator}triggers.json'),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('persists and reloads schedule triggers', () async {
    const trigger = TriggerConfig(
      id: 'morning_water',
      name: 'Morning water',
      prompt: 'Remind me to drink water.',
      type: TriggerType.schedule,
      priority: TriggerPriority.normal,
      scheduleSpec: ScheduleTriggerSpec(hour: 8, minute: 0),
      payload: <String, Object?>{'surface': 'alarm'},
    );

    await repository.upsert(trigger);
    final loaded = await repository.loadAll();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'morning_water');
    expect(loaded.single.scheduleSpec?.hour, 8);
    expect(loaded.single.payload['surface'], 'alarm');
  });

  test('removes persisted triggers', () async {
    const trigger = TriggerConfig(
      id: 'interval_sync',
      name: 'Interval sync',
      prompt: 'Sync every 30 minutes.',
      type: TriggerType.interval,
      priority: TriggerPriority.low,
      intervalSpec: IntervalTriggerSpec(every: Duration(minutes: 30)),
    );

    await repository.upsert(trigger);
    final removed = await repository.remove('interval_sync');

    expect(removed, isTrue);
    expect(await repository.loadAll(), isEmpty);
  });
}
