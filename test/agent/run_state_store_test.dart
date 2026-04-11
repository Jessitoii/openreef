import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/run_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('sqlite run state survives store reconstruction', () async {
    final path = await _tempDatabasePath();
    final createdAt = DateTime.utc(2026, 4, 11, 10);
    final first = SqliteRunStateStore(
      path: path,
      databaseFactory: databaseFactoryFfi,
    );
    await first.initialize();
    await first.save(
      RunState(
        runId: 'run-1',
        requestIdOrigin: 'request-1',
        status: ExecutionLifecycleStatus.suspended,
        mode: ExecutionLifecycleMode.persistentRequest,
        currentStepIndex: 3,
        variables: const <String, Object?>{'branch': 'resume-path'},
        createdAt: createdAt,
        updatedAt: createdAt,
        sessionId: 'system_main',
        waitingReason: 'waiting_event',
        waitingMetadata: const <String, Object?>{'event': 'network_back'},
        resumeToken: 'resume-token',
      ),
    );
    await first.saveTransition(
      RunStateTransition(
        runId: 'run-1',
        from: ExecutionLifecycleStatus.running,
        to: ExecutionLifecycleStatus.suspended,
        reason: 'explicit_suspend',
        occurredAt: createdAt,
        requestId: 'request-1',
      ),
    );
    await first.enqueue(
      QueueAdmissionRecord(
        requestId: 'queued-1',
        runId: 'run-queued',
        sessionId: 'system_main',
        status: QueueAdmissionStatus.queued,
        priority: 10,
        createdAt: createdAt,
        payload: const <String, Object?>{'prompt': 'queued'},
      ),
    );
    await first.saveStandingOrderEvaluations(<StandingOrderEvaluationRecord>[
      StandingOrderEvaluationRecord(
        evaluationId: 'eval-1',
        runId: 'run-1',
        ruleId: 'rule-1',
        triggerType: 'manual',
        condition: const <String, Object?>{'tag': 'critical'},
        action: const <String, Object?>{'type': 'apply_structured_directive'},
        priority: 1,
        status: StandingOrderEvaluationStatus.matchedApplied,
        reason: 'matched',
        evaluatedAt: createdAt,
        displayText: 'display only',
      ),
    ]);
    await first.close();

    final second = SqliteRunStateStore(
      path: path,
      databaseFactory: databaseFactoryFfi,
    );
    await second.initialize();
    addTearDown(second.close);

    final run = await second.byId('run-1');
    expect(run, isNotNull);
    expect(run!.status, ExecutionLifecycleStatus.suspended);
    expect(run.currentStepIndex, 3);
    expect(run.variables['branch'], 'resume-path');
    expect(run.waitingReason, 'waiting_event');
    expect(run.waitingMetadata['event'], 'network_back');
    expect(run.resumeToken, 'resume-token');
    expect(run.transitions.single.reason, 'explicit_suspend');
    expect(
      (await second.queuedForSession('system_main')).single.requestId,
      'queued-1',
    );
    expect(
      (await second.standingOrderEvaluationsForRun('run-1')).single.status,
      StandingOrderEvaluationStatus.matchedApplied,
    );
  });

  test('lifecycle machine rejects illegal terminal transition', () {
    final run = RunState(
      runId: 'run-1',
      requestIdOrigin: 'request-1',
      status: ExecutionLifecycleStatus.completed,
      mode: ExecutionLifecycleMode.persistentRequest,
      currentStepIndex: 0,
      variables: const <String, Object?>{},
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    expect(
      () => const ExecutionLifecycleMachine().transition(
        run: run,
        to: ExecutionLifecycleStatus.running,
        reason: 'invalid',
        at: DateTime.utc(2026),
      ),
      throwsStateError,
    );
  });
}

Future<String> _tempDatabasePath() async {
  final directory = await Directory.systemTemp.createTemp(
    'openreef_run_state_',
  );
  return '${directory.path}${Platform.pathSeparator}execution.sqlite';
}
