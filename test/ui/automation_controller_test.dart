import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_repository.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:openreef/ui/automation_controller.dart';
import 'package:openreef/ui/automation_models.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('automation-controller-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('maps runtime-backed trigger state and persists edits', () async {
    final repository = TriggerRepository(
      file: File('${tempDir.path}${Platform.pathSeparator}triggers.json'),
    );
    final system = TriggerSystem(
      scheduleBackend: _NoopScheduleBackend(),
      intervalBackend: _NoopIntervalBackend(),
      miniKairos: MiniKairos(
        contextLoader: () async => const KairosContext(
          isAppForeground: true,
          batteryLevel: 100,
          activeSubAgents: 0,
        ),
      ),
      taskExecutor: _NoopTaskExecutor(),
    );
    final controller = AutomationController(
      repository: repository,
      triggerSystem: system,
    );

    await controller.saveFromDraft(
      AutomationEditorDraft.create(AutomationEditorKind.schedule).copyWith(
        id: 'morning',
        name: 'Morning',
        actionPrompt: 'Do the morning check.',
      ),
    );
    await controller.initialize();

    expect(controller.timeBasedItems, hasLength(1));
    expect(controller.timeBasedItems.single.runtimeStatusLabel, 'idle');
    expect(controller.timeBasedItems.single.summary, contains('Daily'));

    await controller.setEnabled('morning', false);
    expect(controller.timeBasedItems.single.enabled, isFalse);

    await controller.deleteTrigger('morning');
    expect(controller.allItems, isEmpty);
  });
}

class _NoopScheduleBackend implements ScheduleSchedulerBackend {
  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerSchedule(TriggerConfig trigger) async {}
}

class _NoopIntervalBackend implements IntervalSchedulerBackend {
  @override
  Future<void> cancel(String triggerId) async {}

  @override
  Future<void> registerInterval(TriggerConfig trigger) async {}
}

class _NoopTaskExecutor implements AgentTaskExecutor {
  @override
  Future<ExecutionResult> execute(ExecutionRequest request) async {
    throw UnimplementedError();
  }

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    return const AgentTaskExecutionResult(
      status: AgentTaskExecutionStatus.completed,
      text: '',
      reason: 'noop',
      toolsUsed: <String>[],
    );
  }
}
