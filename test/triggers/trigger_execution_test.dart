import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_system.dart';

void main() {
  test(
    'trigger fire uses executor with background visibility by default',
    () async {
      final executor = _RecordingExecutor();
      final system = TriggerSystem(
        scheduleBackend: _NoopScheduleBackend(),
        intervalBackend: _NoopIntervalBackend(),
        miniKairos: MiniKairos(
          contextLoader: () async => const KairosContext(
            isAppForeground: true,
            batteryLevel: 80,
            activeSubAgents: 0,
          ),
        ),
        taskExecutor: executor,
        systemSessionKey: 'system_main',
      );

      await system.register(
        const TriggerConfig(
          id: 'manual_sync',
          name: 'Manual sync',
          prompt: 'Run a manual maintenance sync.',
          type: TriggerType.manual,
          priority: TriggerPriority.normal,
        ),
      );
      system.setRuntimeReady(true);

      final result = await system.fireManual('manual_sync');

      expect(result.decision, TriggerDecision.execute);
      expect(executor.requests, hasLength(1));
      expect(executor.requests.single.source, ExecutionSource.trigger);
      expect(executor.requests.single.sessionKey, 'system_main');
      expect(
        executor.requests.single.visibility,
        ExecutionVisibility.background,
      );
      expect(
        executor.requests.single.triggerMetadata?.deliveryType,
        TriggerDeliverySource.manual.name,
      );
    },
  );
}

class _RecordingExecutor implements AgentTaskExecutor {
  final List<AgentTaskRequest> requests = <AgentTaskRequest>[];

  @override
  Future<bool> cancelActiveRun({
    String? runId,
    String? sessionKey,
    RunCancellationReason reason = RunCancellationReason.userRequested,
  }) async {
    return false;
  }

  @override
  Future<ExecutionResult> execute(ExecutionRequest request) async {
    throw UnimplementedError();
  }

  @override
  Future<AgentTaskExecutionResult> executeTask(AgentTaskRequest request) async {
    requests.add(request);
    return const AgentTaskExecutionResult(
      status: AgentTaskExecutionStatus.completed,
      text: 'done',
      reason: 'completed',
      toolsUsed: <String>[],
    );
  }
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
