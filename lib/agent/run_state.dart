import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class RunStateTransition {
  const RunStateTransition({
    required this.runId,
    required this.from,
    required this.to,
    required this.reason,
    required this.occurredAt,
    this.requestId,
  });

  final String runId;
  final ExecutionLifecycleStatus from;
  final ExecutionLifecycleStatus to;
  final String reason;
  final DateTime occurredAt;
  final String? requestId;
}

enum QueueAdmissionStatus { queued, claimed, cancelled, completed }

enum StandingOrderEvaluationStatus {
  matchedApplied,
  matchedSkipped,
  notMatched,
}

class StandingOrderEvaluationRecord {
  const StandingOrderEvaluationRecord({
    required this.evaluationId,
    required this.runId,
    required this.ruleId,
    required this.triggerType,
    required this.condition,
    required this.action,
    required this.priority,
    required this.status,
    required this.reason,
    required this.evaluatedAt,
    this.displayText,
  });

  final String evaluationId;
  final String runId;
  final String ruleId;
  final String triggerType;
  final Map<String, Object?> condition;
  final Map<String, Object?> action;
  final int priority;
  final StandingOrderEvaluationStatus status;
  final String reason;
  final DateTime evaluatedAt;
  final String? displayText;
}

class QueueAdmissionRecord {
  const QueueAdmissionRecord({
    required this.requestId,
    required this.runId,
    required this.sessionId,
    required this.status,
    required this.priority,
    required this.createdAt,
    this.claimedAt,
    this.reason,
    this.coalesceKey,
    this.payload = const <String, Object?>{},
  });

  final String requestId;
  final String runId;
  final String sessionId;
  final QueueAdmissionStatus status;
  final int priority;
  final DateTime createdAt;
  final DateTime? claimedAt;
  final String? reason;
  final String? coalesceKey;
  final Map<String, Object?> payload;
}

class RunState {
  const RunState({
    required this.runId,
    required this.requestIdOrigin,
    required this.status,
    required this.mode,
    required this.currentStepIndex,
    required this.variables,
    required this.createdAt,
    required this.updatedAt,
    this.sessionId,
    this.workflowId,
    this.lastAction,
    this.lastToolResultRef,
    this.waitingReason,
    this.waitingMetadata = const <String, Object?>{},
    this.resumeToken,
    this.completedAt,
    this.terminalReason,
    this.cancelRequested = false,
    this.supersededByRequestId,
    this.supersedesRunId,
    this.coalescedEventRefs = const <String>[],
    this.transitions = const <RunStateTransition>[],
  });

  final String runId;
  final String requestIdOrigin;
  final ExecutionLifecycleStatus status;
  final ExecutionLifecycleMode mode;
  final int currentStepIndex;
  final Map<String, Object?> variables;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sessionId;
  final String? workflowId;
  final String? lastAction;
  final String? lastToolResultRef;
  final String? waitingReason;
  final Map<String, Object?> waitingMetadata;
  final String? resumeToken;
  final DateTime? completedAt;
  final String? terminalReason;
  final bool cancelRequested;
  final String? supersededByRequestId;
  final String? supersedesRunId;
  final List<String> coalescedEventRefs;
  final List<RunStateTransition> transitions;

  bool get isActive =>
      status == ExecutionLifecycleStatus.queued ||
      status == ExecutionLifecycleStatus.running ||
      status == ExecutionLifecycleStatus.suspended;

  bool get isTerminal =>
      status == ExecutionLifecycleStatus.completed ||
      status == ExecutionLifecycleStatus.failed ||
      status == ExecutionLifecycleStatus.cancelled ||
      status == ExecutionLifecycleStatus.rejected;

  bool get isResumable => status == ExecutionLifecycleStatus.suspended;

  RunState copyWith({
    ExecutionLifecycleStatus? status,
    int? currentStepIndex,
    Map<String, Object?>? variables,
    DateTime? updatedAt,
    String? lastAction,
    String? lastToolResultRef,
    String? waitingReason,
    bool clearWaitingReason = false,
    Map<String, Object?>? waitingMetadata,
    DateTime? completedAt,
    String? terminalReason,
    bool? cancelRequested,
    String? supersededByRequestId,
    String? supersedesRunId,
    List<String>? coalescedEventRefs,
    List<RunStateTransition>? transitions,
  }) {
    return RunState(
      runId: runId,
      requestIdOrigin: requestIdOrigin,
      status: status ?? this.status,
      mode: mode,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      variables: Map<String, Object?>.unmodifiable(variables ?? this.variables),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionId: sessionId,
      workflowId: workflowId,
      lastAction: lastAction ?? this.lastAction,
      lastToolResultRef: lastToolResultRef ?? this.lastToolResultRef,
      waitingReason: clearWaitingReason
          ? null
          : waitingReason ?? this.waitingReason,
      waitingMetadata: Map<String, Object?>.unmodifiable(
        waitingMetadata ?? this.waitingMetadata,
      ),
      resumeToken: resumeToken,
      completedAt: completedAt ?? this.completedAt,
      terminalReason: terminalReason ?? this.terminalReason,
      cancelRequested: cancelRequested ?? this.cancelRequested,
      supersededByRequestId:
          supersededByRequestId ?? this.supersededByRequestId,
      supersedesRunId: supersedesRunId ?? this.supersedesRunId,
      coalescedEventRefs: List<String>.unmodifiable(
        coalescedEventRefs ?? this.coalescedEventRefs,
      ),
      transitions: List<RunStateTransition>.unmodifiable(
        transitions ?? this.transitions,
      ),
    );
  }
}

class ExecutionLifecycleMachine {
  const ExecutionLifecycleMachine();

  bool canTransition(
    ExecutionLifecycleStatus from,
    ExecutionLifecycleStatus to,
  ) {
    if (_isTerminal(from)) {
      return false;
    }
    return switch (from) {
      ExecutionLifecycleStatus.queued =>
        to == ExecutionLifecycleStatus.running ||
            to == ExecutionLifecycleStatus.cancelled ||
            to == ExecutionLifecycleStatus.rejected,
      ExecutionLifecycleStatus.running =>
        to == ExecutionLifecycleStatus.suspended ||
            to == ExecutionLifecycleStatus.completed ||
            to == ExecutionLifecycleStatus.failed ||
            to == ExecutionLifecycleStatus.cancelled,
      ExecutionLifecycleStatus.suspended =>
        to == ExecutionLifecycleStatus.running ||
            to == ExecutionLifecycleStatus.cancelled ||
            to == ExecutionLifecycleStatus.failed,
      ExecutionLifecycleStatus.completed ||
      ExecutionLifecycleStatus.failed ||
      ExecutionLifecycleStatus.cancelled ||
      ExecutionLifecycleStatus.rejected => false,
    };
  }

  RunState transition({
    required RunState run,
    required ExecutionLifecycleStatus to,
    required String reason,
    required DateTime at,
    String? requestId,
    int? currentStepIndex,
    Map<String, Object?>? variables,
    String? waitingReason,
    Map<String, Object?>? waitingMetadata,
    String? terminalReason,
    bool clearWaitingReason = false,
  }) {
    if (!canTransition(run.status, to)) {
      throw StateError('illegal_transition:${run.status.name}->${to.name}');
    }
    final transition = RunStateTransition(
      runId: run.runId,
      from: run.status,
      to: to,
      reason: reason,
      occurredAt: at.toUtc(),
      requestId: requestId,
    );
    return run.copyWith(
      status: to,
      currentStepIndex: currentStepIndex,
      variables: variables,
      updatedAt: at.toUtc(),
      waitingReason: waitingReason,
      clearWaitingReason: clearWaitingReason,
      waitingMetadata: waitingMetadata,
      completedAt: _isTerminal(to) ? at.toUtc() : null,
      terminalReason: terminalReason,
      transitions: <RunStateTransition>[...run.transitions, transition],
    );
  }

  static bool _isTerminal(ExecutionLifecycleStatus status) {
    return status == ExecutionLifecycleStatus.completed ||
        status == ExecutionLifecycleStatus.failed ||
        status == ExecutionLifecycleStatus.cancelled ||
        status == ExecutionLifecycleStatus.rejected;
  }
}

abstract class RunStateStore {
  ValueListenable<List<RunState>> get runs;

  Future<void> initialize();

  Future<RunState?> byId(String runId);

  Future<List<RunState>> activeForSession(String sessionId);

  Future<List<RunState>> activeByCoalesceKey(String coalesceKey);

  Future<void> save(RunState runState);

  Future<void> saveTransition(RunStateTransition transition);

  Future<void> enqueue(QueueAdmissionRecord record);

  Future<List<QueueAdmissionRecord>> queuedForSession(String sessionId);

  Future<void> updateQueueStatus(
    String requestId,
    QueueAdmissionStatus status, {
    DateTime? claimedAt,
    String? reason,
  });

  Future<void> saveStandingOrderEvaluations(
    List<StandingOrderEvaluationRecord> evaluations,
  );

  Future<List<StandingOrderEvaluationRecord>> standingOrderEvaluationsForRun(
    String runId,
  );

  Future<void> close();
}

class InMemoryRunStateStore implements RunStateStore {
  final ValueNotifier<List<RunState>> _runs = ValueNotifier<List<RunState>>(
    const <RunState>[],
  );

  final Map<String, RunState> _byId = <String, RunState>{};
  final Map<String, QueueAdmissionRecord> _queue =
      <String, QueueAdmissionRecord>{};
  final List<StandingOrderEvaluationRecord> _evaluations =
      <StandingOrderEvaluationRecord>[];

  @override
  ValueListenable<List<RunState>> get runs => _runs;

  @override
  Future<void> initialize() async {}

  @override
  Future<RunState?> byId(String runId) async => _byId[runId];

  @override
  Future<List<RunState>> activeForSession(String sessionId) async {
    return _byId.values
        .where((run) => run.sessionId == sessionId && run.isActive)
        .toList(growable: false);
  }

  @override
  Future<List<RunState>> activeByCoalesceKey(String coalesceKey) async {
    return _byId.values
        .where(
          (run) =>
              run.isActive &&
              (run.runId == coalesceKey ||
                  run.coalescedEventRefs.contains(coalesceKey)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> save(RunState runState) async {
    _byId[runState.runId] = runState;
    _runs.value = List<RunState>.unmodifiable(_byId.values);
  }

  @override
  Future<void> saveTransition(RunStateTransition transition) async {}

  @override
  Future<void> enqueue(QueueAdmissionRecord record) async {
    _queue[record.requestId] = record;
  }

  @override
  Future<List<QueueAdmissionRecord>> queuedForSession(String sessionId) async {
    final rows = _queue.values
        .where(
          (record) =>
              record.sessionId == sessionId &&
              record.status == QueueAdmissionStatus.queued,
        )
        .toList(growable: false);
    rows.sort((left, right) {
      final priority = right.priority.compareTo(left.priority);
      return priority != 0
          ? priority
          : left.createdAt.compareTo(right.createdAt);
    });
    return rows;
  }

  @override
  Future<void> updateQueueStatus(
    String requestId,
    QueueAdmissionStatus status, {
    DateTime? claimedAt,
    String? reason,
  }) async {
    final record = _queue[requestId];
    if (record == null) {
      return;
    }
    _queue[requestId] = QueueAdmissionRecord(
      requestId: record.requestId,
      runId: record.runId,
      sessionId: record.sessionId,
      status: status,
      priority: record.priority,
      createdAt: record.createdAt,
      claimedAt: claimedAt ?? record.claimedAt,
      reason: reason ?? record.reason,
      coalesceKey: record.coalesceKey,
      payload: record.payload,
    );
  }

  @override
  Future<void> saveStandingOrderEvaluations(
    List<StandingOrderEvaluationRecord> evaluations,
  ) async {
    _evaluations.removeWhere(
      (existing) =>
          evaluations.any((next) => next.evaluationId == existing.evaluationId),
    );
    _evaluations.addAll(evaluations);
  }

  @override
  Future<List<StandingOrderEvaluationRecord>> standingOrderEvaluationsForRun(
    String runId,
  ) async {
    return _evaluations
        .where((evaluation) => evaluation.runId == runId)
        .toList(growable: false);
  }

  @override
  Future<void> close() async {}
}

class SqliteRunStateStore implements RunStateStore {
  SqliteRunStateStore({String? path, DatabaseFactory? databaseFactory})
    : _path = path,
      _databaseFactory = databaseFactory;

  static const String _databaseName = 'openreef_execution.sqlite';
  static const String _runsTable = 'execution_runs';
  static const String _transitionsTable = 'execution_run_transitions';
  static const String _queueTable = 'execution_queue';
  static const String _standingOrdersTable = 'standing_order_evaluations';

  final String? _path;
  final DatabaseFactory? _databaseFactory;
  final ValueNotifier<List<RunState>> _runs = ValueNotifier<List<RunState>>(
    const <RunState>[],
  );

  Database? _database;

  @override
  ValueListenable<List<RunState>> get runs => _runs;

  @override
  Future<void> initialize() async {
    if (_database != null) {
      return;
    }
    final factory = _databaseFactory ?? _resolveDatabaseFactory();
    final dbPath = _path ?? await _defaultDatabasePath(factory);
    _database = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createSchema,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    await _refreshRuns();
  }

  Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE $_runsTable (
        run_id TEXT PRIMARY KEY,
        request_id_origin TEXT NOT NULL,
        status TEXT NOT NULL,
        mode TEXT NOT NULL,
        current_step_index INTEGER NOT NULL,
        variables_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        session_id TEXT,
        workflow_id TEXT,
        last_action TEXT,
        last_tool_result_ref TEXT,
        waiting_reason TEXT,
        waiting_metadata_json TEXT NOT NULL,
        resume_token TEXT,
        completed_at TEXT,
        terminal_reason TEXT,
        cancel_requested INTEGER NOT NULL,
        superseded_by_request_id TEXT,
        supersedes_run_id TEXT,
        coalesced_event_refs_json TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE $_transitionsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id TEXT NOT NULL,
        request_id TEXT,
        from_status TEXT NOT NULL,
        to_status TEXT NOT NULL,
        reason TEXT NOT NULL,
        occurred_at TEXT NOT NULL,
        FOREIGN KEY(run_id) REFERENCES $_runsTable(run_id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE $_queueTable (
        request_id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        status TEXT NOT NULL,
        priority INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        claimed_at TEXT,
        reason TEXT,
        coalesce_key TEXT,
        payload_json TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE $_standingOrdersTable (
        evaluation_id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL,
        rule_id TEXT NOT NULL,
        trigger_type TEXT NOT NULL,
        condition_json TEXT NOT NULL,
        action_json TEXT NOT NULL,
        priority INTEGER NOT NULL,
        status TEXT NOT NULL,
        reason TEXT NOT NULL,
        evaluated_at TEXT NOT NULL,
        display_text TEXT,
        FOREIGN KEY(run_id) REFERENCES $_runsTable(run_id) ON DELETE CASCADE
      )
    ''');
    await database.execute(
      'CREATE INDEX idx_execution_runs_session ON $_runsTable(session_id, status)',
    );
    await database.execute(
      'CREATE INDEX idx_execution_queue_session ON $_queueTable(session_id, status, priority, created_at)',
    );
  }

  @override
  Future<RunState?> byId(String runId) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      _runsTable,
      where: 'run_id = ?',
      whereArgs: <Object?>[runId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _runFromRow(rows.single, await _transitionsForRun(runId));
  }

  @override
  Future<List<RunState>> activeForSession(String sessionId) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      _runsTable,
      where: 'session_id = ? AND status IN (?, ?, ?)',
      whereArgs: <Object?>[
        sessionId,
        ExecutionLifecycleStatus.queued.name,
        ExecutionLifecycleStatus.running.name,
        ExecutionLifecycleStatus.suspended.name,
      ],
    );
    final runs = <RunState>[];
    for (final row in rows) {
      runs.add(
        _runFromRow(row, await _transitionsForRun(row['run_id'] as String)),
      );
    }
    return runs;
  }

  @override
  Future<List<RunState>> activeByCoalesceKey(String coalesceKey) async {
    final active = <RunState>[];
    for (final run in _runs.value) {
      if (!run.isActive) {
        continue;
      }
      if (run.runId == coalesceKey ||
          run.coalescedEventRefs.contains(coalesceKey)) {
        active.add(run);
      }
    }
    return active;
  }

  @override
  Future<void> save(RunState runState) async {
    final database = await _requireDatabase();
    final existing = await database.query(
      _runsTable,
      columns: const <String>['run_id'],
      where: 'run_id = ?',
      whereArgs: <Object?>[runState.runId],
      limit: 1,
    );
    if (existing.isEmpty) {
      await database.insert(_runsTable, _runToRow(runState));
    } else {
      await database.update(
        _runsTable,
        _runToRow(runState),
        where: 'run_id = ?',
        whereArgs: <Object?>[runState.runId],
      );
    }
    await _refreshRuns();
  }

  @override
  Future<void> saveTransition(RunStateTransition transition) async {
    final database = await _requireDatabase();
    await database.insert(_transitionsTable, _transitionToRow(transition));
  }

  @override
  Future<void> enqueue(QueueAdmissionRecord record) async {
    final database = await _requireDatabase();
    await database.insert(
      _queueTable,
      _queueToRow(record),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<QueueAdmissionRecord>> queuedForSession(String sessionId) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      _queueTable,
      where: 'session_id = ? AND status = ?',
      whereArgs: <Object?>[sessionId, QueueAdmissionStatus.queued.name],
      orderBy: 'priority DESC, created_at ASC',
    );
    return rows.map(_queueFromRow).toList(growable: false);
  }

  @override
  Future<void> updateQueueStatus(
    String requestId,
    QueueAdmissionStatus status, {
    DateTime? claimedAt,
    String? reason,
  }) async {
    final database = await _requireDatabase();
    final values = <String, Object?>{
      'status': status.name,
      if (claimedAt != null) 'claimed_at': claimedAt.toUtc().toIso8601String(),
    };
    if (reason != null) {
      values['reason'] = reason;
    }
    await database.update(
      _queueTable,
      values,
      where: 'request_id = ?',
      whereArgs: <Object?>[requestId],
    );
  }

  @override
  Future<void> saveStandingOrderEvaluations(
    List<StandingOrderEvaluationRecord> evaluations,
  ) async {
    if (evaluations.isEmpty) {
      return;
    }
    final database = await _requireDatabase();
    await database.transaction((transaction) async {
      for (final evaluation in evaluations) {
        await transaction.insert(
          _standingOrdersTable,
          _standingOrderToRow(evaluation),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<StandingOrderEvaluationRecord>> standingOrderEvaluationsForRun(
    String runId,
  ) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      _standingOrdersTable,
      where: 'run_id = ?',
      whereArgs: <Object?>[runId],
      orderBy: 'priority DESC, evaluated_at ASC',
    );
    return rows.map(_standingOrderFromRow).toList(growable: false);
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Database> _requireDatabase() async {
    await initialize();
    return _database!;
  }

  Future<void> _refreshRuns() async {
    final database = await _requireDatabase();
    final rows = await database.query(_runsTable, orderBy: 'created_at ASC');
    final loaded = <RunState>[];
    for (final row in rows) {
      loaded.add(
        _runFromRow(row, await _transitionsForRun(row['run_id'] as String)),
      );
    }
    _runs.value = List<RunState>.unmodifiable(loaded);
  }

  Future<List<RunStateTransition>> _transitionsForRun(String runId) async {
    final database = await _requireDatabase();
    final rows = await database.query(
      _transitionsTable,
      where: 'run_id = ?',
      whereArgs: <Object?>[runId],
      orderBy: 'occurred_at ASC, id ASC',
    );
    return rows.map(_transitionFromRow).toList(growable: false);
  }

  Map<String, Object?> _runToRow(RunState run) {
    return <String, Object?>{
      'run_id': run.runId,
      'request_id_origin': run.requestIdOrigin,
      'status': run.status.name,
      'mode': run.mode.name,
      'current_step_index': run.currentStepIndex,
      'variables_json': jsonEncode(run.variables),
      'created_at': run.createdAt.toUtc().toIso8601String(),
      'updated_at': run.updatedAt.toUtc().toIso8601String(),
      'session_id': run.sessionId,
      'workflow_id': run.workflowId,
      'last_action': run.lastAction,
      'last_tool_result_ref': run.lastToolResultRef,
      'waiting_reason': run.waitingReason,
      'waiting_metadata_json': jsonEncode(run.waitingMetadata),
      'resume_token': run.resumeToken,
      'completed_at': run.completedAt?.toUtc().toIso8601String(),
      'terminal_reason': run.terminalReason,
      'cancel_requested': run.cancelRequested ? 1 : 0,
      'superseded_by_request_id': run.supersededByRequestId,
      'supersedes_run_id': run.supersedesRunId,
      'coalesced_event_refs_json': jsonEncode(run.coalescedEventRefs),
    };
  }

  RunState _runFromRow(
    Map<String, Object?> row,
    List<RunStateTransition> transitions,
  ) {
    return RunState(
      runId: row['run_id'] as String,
      requestIdOrigin: row['request_id_origin'] as String,
      status: _statusFromName(row['status'] as String),
      mode: _modeFromName(row['mode'] as String),
      currentStepIndex: row['current_step_index'] as int,
      variables: _decodeMap(row['variables_json'] as String),
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
      sessionId: row['session_id'] as String?,
      workflowId: row['workflow_id'] as String?,
      lastAction: row['last_action'] as String?,
      lastToolResultRef: row['last_tool_result_ref'] as String?,
      waitingReason: row['waiting_reason'] as String?,
      waitingMetadata: _decodeMap(row['waiting_metadata_json'] as String),
      resumeToken: row['resume_token'] as String?,
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String).toUtc(),
      terminalReason: row['terminal_reason'] as String?,
      cancelRequested: row['cancel_requested'] == 1,
      supersededByRequestId: row['superseded_by_request_id'] as String?,
      supersedesRunId: row['supersedes_run_id'] as String?,
      coalescedEventRefs: _decodeStringList(
        row['coalesced_event_refs_json'] as String,
      ),
      transitions: transitions,
    );
  }

  Map<String, Object?> _transitionToRow(RunStateTransition transition) {
    return <String, Object?>{
      'run_id': transition.runId,
      'request_id': transition.requestId,
      'from_status': transition.from.name,
      'to_status': transition.to.name,
      'reason': transition.reason,
      'occurred_at': transition.occurredAt.toUtc().toIso8601String(),
    };
  }

  RunStateTransition _transitionFromRow(Map<String, Object?> row) {
    return RunStateTransition(
      runId: row['run_id'] as String,
      requestId: row['request_id'] as String?,
      from: _statusFromName(row['from_status'] as String),
      to: _statusFromName(row['to_status'] as String),
      reason: row['reason'] as String,
      occurredAt: DateTime.parse(row['occurred_at'] as String).toUtc(),
    );
  }

  Map<String, Object?> _queueToRow(QueueAdmissionRecord record) {
    return <String, Object?>{
      'request_id': record.requestId,
      'run_id': record.runId,
      'session_id': record.sessionId,
      'status': record.status.name,
      'priority': record.priority,
      'created_at': record.createdAt.toUtc().toIso8601String(),
      'claimed_at': record.claimedAt?.toUtc().toIso8601String(),
      'reason': record.reason,
      'coalesce_key': record.coalesceKey,
      'payload_json': jsonEncode(record.payload),
    };
  }

  QueueAdmissionRecord _queueFromRow(Map<String, Object?> row) {
    return QueueAdmissionRecord(
      requestId: row['request_id'] as String,
      runId: row['run_id'] as String,
      sessionId: row['session_id'] as String,
      status: _queueStatusFromName(row['status'] as String),
      priority: row['priority'] as int,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
      claimedAt: row['claimed_at'] == null
          ? null
          : DateTime.parse(row['claimed_at'] as String).toUtc(),
      reason: row['reason'] as String?,
      coalesceKey: row['coalesce_key'] as String?,
      payload: _decodeMap(row['payload_json'] as String),
    );
  }

  Map<String, Object?> _standingOrderToRow(
    StandingOrderEvaluationRecord evaluation,
  ) {
    return <String, Object?>{
      'evaluation_id': evaluation.evaluationId,
      'run_id': evaluation.runId,
      'rule_id': evaluation.ruleId,
      'trigger_type': evaluation.triggerType,
      'condition_json': jsonEncode(evaluation.condition),
      'action_json': jsonEncode(evaluation.action),
      'priority': evaluation.priority,
      'status': evaluation.status.name,
      'reason': evaluation.reason,
      'evaluated_at': evaluation.evaluatedAt.toUtc().toIso8601String(),
      'display_text': evaluation.displayText,
    };
  }

  StandingOrderEvaluationRecord _standingOrderFromRow(
    Map<String, Object?> row,
  ) {
    return StandingOrderEvaluationRecord(
      evaluationId: row['evaluation_id'] as String,
      runId: row['run_id'] as String,
      ruleId: row['rule_id'] as String,
      triggerType: row['trigger_type'] as String,
      condition: _decodeMap(row['condition_json'] as String),
      action: _decodeMap(row['action_json'] as String),
      priority: row['priority'] as int,
      status: _standingOrderStatusFromName(row['status'] as String),
      reason: row['reason'] as String,
      evaluatedAt: DateTime.parse(row['evaluated_at'] as String).toUtc(),
      displayText: row['display_text'] as String?,
    );
  }

  DatabaseFactory _resolveDatabaseFactory() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return databaseFactorySqflitePlugin;
  }

  Future<String> _defaultDatabasePath(DatabaseFactory factory) async {
    final basePath = await factory.getDatabasesPath();
    return p.join(basePath, _databaseName);
  }
}

ExecutionLifecycleStatus _statusFromName(String value) {
  return ExecutionLifecycleStatus.values.firstWhere(
    (status) => status.name == value,
  );
}

ExecutionLifecycleMode _modeFromName(String value) {
  return ExecutionLifecycleMode.values.firstWhere((mode) => mode.name == value);
}

QueueAdmissionStatus _queueStatusFromName(String value) {
  return QueueAdmissionStatus.values.firstWhere(
    (status) => status.name == value,
  );
}

StandingOrderEvaluationStatus _standingOrderStatusFromName(String value) {
  return StandingOrderEvaluationStatus.values.firstWhere(
    (status) => status.name == value,
  );
}

Map<String, Object?> _decodeMap(String value) {
  final decoded = jsonDecode(value);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return Map<String, Object?>.from(decoded);
  }
  return const <String, Object?>{};
}

List<String> _decodeStringList(String value) {
  final decoded = jsonDecode(value);
  if (decoded is List) {
    return decoded.map((entry) => entry.toString()).toList(growable: false);
  }
  return const <String>[];
}
