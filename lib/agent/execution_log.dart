import 'package:flutter/foundation.dart';
import 'package:openreef/agent/execution_request.dart';

enum ExecutionStatus { running, completed, failed, frozen }

class ExecutionRecord {
  const ExecutionRecord({
    required this.id,
    required this.sessionKey,
    required this.source,
    required this.status,
    required this.toolsUsed,
    required this.createdAt,
    this.finishedAt,
    this.failureReason,
    this.errorSummary,
  });

  final String id;
  final String sessionKey;
  final ExecutionSource source;
  final ExecutionStatus status;
  final List<String> toolsUsed;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final String? failureReason;
  final String? errorSummary;

  ExecutionRecord copyWith({
    ExecutionStatus? status,
    List<String>? toolsUsed,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    String? failureReason,
    bool clearFailureReason = false,
    String? errorSummary,
    bool clearErrorSummary = false,
  }) {
    return ExecutionRecord(
      id: id,
      sessionKey: sessionKey,
      source: source,
      status: status ?? this.status,
      toolsUsed: List<String>.unmodifiable(toolsUsed ?? this.toolsUsed),
      createdAt: createdAt,
      finishedAt: clearFinishedAt ? null : finishedAt ?? this.finishedAt,
      failureReason: clearFailureReason
          ? null
          : failureReason ?? this.failureReason,
      errorSummary: clearErrorSummary ? null : errorSummary ?? this.errorSummary,
    );
  }
}

abstract class ExecutionLogStore {
  ValueListenable<List<ExecutionRecord>> get records;

  void start(ExecutionRecord record);

  void complete(
    String id, {
    required ExecutionStatus status,
    required List<String> toolsUsed,
    required DateTime finishedAt,
    String? failureReason,
    String? errorSummary,
  });
}

class InMemoryExecutionLogStore implements ExecutionLogStore {
  final ValueNotifier<List<ExecutionRecord>> _records =
      ValueNotifier<List<ExecutionRecord>>(const <ExecutionRecord>[]);

  @override
  ValueListenable<List<ExecutionRecord>> get records => _records;

  @override
  void start(ExecutionRecord record) {
    _records.value = List<ExecutionRecord>.unmodifiable(
      <ExecutionRecord>[..._records.value, record],
    );
  }

  @override
  void complete(
    String id, {
    required ExecutionStatus status,
    required List<String> toolsUsed,
    required DateTime finishedAt,
    String? failureReason,
    String? errorSummary,
  }) {
    final updated = _records.value.map((record) {
      if (record.id != id) {
        return record;
      }
      return record.copyWith(
        status: status,
        toolsUsed: List<String>.unmodifiable(toolsUsed),
        finishedAt: finishedAt.toUtc(),
        failureReason: failureReason,
        clearFailureReason: failureReason == null,
        errorSummary: errorSummary,
        clearErrorSummary: errorSummary == null,
      );
    }).toList(growable: false);
    _records.value = List<ExecutionRecord>.unmodifiable(updated);
  }
}
