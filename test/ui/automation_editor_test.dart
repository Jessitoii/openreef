import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/triggers/mini_kairos.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_repository.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:openreef/ui/automation_builder_screen.dart';
import 'package:openreef/ui/automation_controller.dart';
import 'package:openreef/ui/automation_models.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('automation-editor-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('builder keeps advanced fields hidden by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AutomationBuilderScreen(
          controller: AutomationController(
            repository: TriggerRepository(
              file: File(
                '${tempDir.path}${Platform.pathSeparator}triggers.json',
              ),
            ),
            triggerSystem: TriggerSystem(
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
            ),
          ),
          initialDraft: AutomationEditorDraft.create(
            AutomationEditorKind.schedule,
          ),
        ),
      ),
    );

    expect(find.text('Cron expression'), findsNothing);
    expect(find.text('Source id'), findsNothing);
    expect(find.text('Event id'), findsNothing);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();

    expect(find.text('Cron expression'), findsOneWidget);
    expect(find.text('Source id'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Event id'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Event id'), findsOneWidget);
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
