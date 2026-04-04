enum AutoDreamRunStatus { completed, skippedAlreadyRunning }

class AutoDreamRunResult {
  const AutoDreamRunResult({
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.sessionsScanned,
    required this.sessionsSummarized,
    required this.memoriesWritten,
    required this.memoryKeys,
  });

  const AutoDreamRunResult.skipped({
    required DateTime at,
  }) : this(
         status: AutoDreamRunStatus.skippedAlreadyRunning,
         startedAt: at,
         finishedAt: at,
         sessionsScanned: 0,
         sessionsSummarized: 0,
         memoriesWritten: 0,
         memoryKeys: const <String>[],
       );

  final AutoDreamRunStatus status;
  final DateTime startedAt;
  final DateTime finishedAt;
  final int sessionsScanned;
  final int sessionsSummarized;
  final int memoriesWritten;
  final List<String> memoryKeys;

  bool get didRun => status == AutoDreamRunStatus.completed;
}
