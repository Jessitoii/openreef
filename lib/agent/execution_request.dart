enum ExecutionSource { user, trigger, schedule, mcpEvent, resumeSignal, system }

enum ExecutionVisibility { chat, background, chatAndBackground }

enum ExecutionLifecycleMode {
  ephemeralRequest,
  persistentRequest,
  resumeRequest,
  triggeredRequest,
}

enum ExecutionLifecycleStatus {
  queued,
  running,
  suspended,
  completed,
  failed,
  cancelled,
  rejected,
}

enum ExecutionClassificationConfidence { ruleBased, llmAssistedStructured }

enum DuplicateExecutionPolicy { allow, reject, replaceRunning, coalesce, queue }

enum QueueExecutionPolicy { fifo, priority, noneReject }

enum FailureExecutionPolicy { failRun, freezeRun }

enum CompletionExecutionPolicy { emitChatResponse, stateOnly, both }

enum ExecutionAttachmentType { image, audio, document, voiceMessage }

class ExecutionAttachment {
  const ExecutionAttachment({
    required this.id,
    required this.type,
    required this.displayName,
    this.sizeBytes,
    this.mimeType,
    this.sourceUri,
  });

  final String id;
  final ExecutionAttachmentType type;
  final String displayName;
  final int? sizeBytes;
  final String? mimeType;
  final String? sourceUri;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'type': type.name,
      'displayName': displayName,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      if (mimeType != null) 'mimeType': mimeType,
      if (sourceUri != null) 'sourceUri': sourceUri,
    };
  }
}

class ExecutionClassifierOutput {
  const ExecutionClassifierOutput({
    required this.mode,
    required this.classificationReason,
    this.confidenceLevel = ExecutionClassificationConfidence.ruleBased,
  });

  final ExecutionLifecycleMode mode;
  final String classificationReason;
  final ExecutionClassificationConfidence confidenceLevel;
}

class ExecutionPolicy {
  const ExecutionPolicy({
    required this.allowToolUse,
    required this.allowPersistence,
    required this.allowSuspend,
    required this.maxSteps,
    required this.maxToolCalls,
    required this.timeoutMs,
    required this.duplicatePolicy,
    required this.queuePolicy,
    required this.failurePolicy,
    required this.completionPolicy,
    this.coalesceKey,
  });

  final bool allowToolUse;
  final bool allowPersistence;
  final bool allowSuspend;
  final int maxSteps;
  final int maxToolCalls;
  final int timeoutMs;
  final DuplicateExecutionPolicy duplicatePolicy;
  final QueueExecutionPolicy queuePolicy;
  final FailureExecutionPolicy failurePolicy;
  final CompletionExecutionPolicy completionPolicy;
  final String? coalesceKey;

  factory ExecutionPolicy.forRequest({
    required ExecutionLifecycleMode mode,
    required ExecutionSource source,
    ExecutionVisibility? visibility,
    Map<String, dynamic>? metadata,
  }) {
    final duplicateKey = metadata?['duplicateKey'] as String?;
    final standingOrderIds =
        (metadata?['appliedStandingOrderIds'] as List?)?.isNotEmpty ?? false;
    if (source == ExecutionSource.user) {
      return const ExecutionPolicy(
        allowToolUse: true,
        allowPersistence: false,
        allowSuspend: false,
        maxSteps: 12,
        maxToolCalls: 8,
        timeoutMs: 30000,
        duplicatePolicy: DuplicateExecutionPolicy.reject,
        queuePolicy: QueueExecutionPolicy.noneReject,
        failurePolicy: FailureExecutionPolicy.failRun,
        completionPolicy: CompletionExecutionPolicy.emitChatResponse,
      );
    }
    if (mode == ExecutionLifecycleMode.resumeRequest) {
      return const ExecutionPolicy(
        allowToolUse: true,
        allowPersistence: true,
        allowSuspend: true,
        maxSteps: 12,
        maxToolCalls: 8,
        timeoutMs: 120000,
        duplicatePolicy: DuplicateExecutionPolicy.reject,
        queuePolicy: QueueExecutionPolicy.priority,
        failurePolicy: FailureExecutionPolicy.failRun,
        completionPolicy: CompletionExecutionPolicy.both,
      );
    }
    if (source == ExecutionSource.mcpEvent) {
      return ExecutionPolicy(
        allowToolUse: true,
        allowPersistence: true,
        allowSuspend: true,
        maxSteps: 12,
        maxToolCalls: 8,
        timeoutMs: 90000,
        duplicatePolicy: DuplicateExecutionPolicy.coalesce,
        queuePolicy: QueueExecutionPolicy.fifo,
        failurePolicy: FailureExecutionPolicy.failRun,
        completionPolicy: CompletionExecutionPolicy.both,
        coalesceKey: duplicateKey,
      );
    }
    return ExecutionPolicy(
      allowToolUse: true,
      allowPersistence: true,
      allowSuspend: true,
      maxSteps: 12,
      maxToolCalls: 8,
      timeoutMs: 120000,
      duplicatePolicy: standingOrderIds
          ? DuplicateExecutionPolicy.reject
          : DuplicateExecutionPolicy.queue,
      queuePolicy: QueueExecutionPolicy.fifo,
      failurePolicy: FailureExecutionPolicy.failRun,
      completionPolicy: visibility == ExecutionVisibility.background
          ? CompletionExecutionPolicy.both
          : CompletionExecutionPolicy.emitChatResponse,
      coalesceKey: duplicateKey,
    );
  }
}

class RunContext {
  const RunContext({
    required this.runId,
    this.workflowId,
    this.resumeToken,
    this.currentStepIndex = 0,
    this.variables = const <String, Object?>{},
    this.waitingReason,
    this.waitingMetadata = const <String, Object?>{},
  });

  final String runId;
  final String? workflowId;
  final String? resumeToken;
  final int currentStepIndex;
  final Map<String, Object?> variables;
  final String? waitingReason;
  final Map<String, Object?> waitingMetadata;
}

class ExecutionRequest {
  const ExecutionRequest({
    required this.id,
    required this.source,
    required this.sessionKey,
    required this.prompt,
    required this.visibility,
    required this.createdAt,
    required this.classification,
    required this.policy,
    this.attachments = const <ExecutionAttachment>[],
    this.metadata,
    this.runContext,
  });

  final String id;
  final ExecutionSource source;
  final String sessionKey;
  final String prompt;
  final Map<String, dynamic>? metadata;
  final ExecutionVisibility visibility;
  final DateTime createdAt;
  final ExecutionClassifierOutput classification;
  final ExecutionPolicy policy;
  final List<ExecutionAttachment> attachments;
  final RunContext? runContext;

  ExecutionLifecycleMode get mode => classification.mode;

  factory ExecutionRequest.fromUserMessage({
    required String sessionKey,
    required String prompt,
    Map<String, dynamic>? metadata,
    List<ExecutionAttachment> attachments = const <ExecutionAttachment>[],
    String? id,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.chat,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final classification = ExecutionClassifier.classify(
      source: ExecutionSource.user,
      metadata: metadata,
    );
    return ExecutionRequest(
      id: id ?? _defaultId(ExecutionSource.user, timestamp),
      source: ExecutionSource.user,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: metadata == null ? null : Map<String, dynamic>.from(metadata),
      attachments: List<ExecutionAttachment>.unmodifiable(attachments),
      visibility: visibility,
      createdAt: timestamp,
      classification: classification,
      policy: ExecutionPolicy.forRequest(
        mode: classification.mode,
        source: ExecutionSource.user,
        visibility: visibility,
        metadata: metadata,
      ),
    );
  }

  factory ExecutionRequest.fromTrigger({
    required String sessionKey,
    required String prompt,
    required ExecutionSource source,
    Map<String, dynamic>? metadata,
    String? id,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.background,
  }) {
    assert(
      source == ExecutionSource.trigger || source == ExecutionSource.schedule,
      'Trigger execution source must be trigger or schedule.',
    );
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final effectiveSource = source;
    final classification = ExecutionClassifier.classify(
      source: effectiveSource,
      metadata: metadata,
    );
    final runId =
        metadata?['runId'] as String? ?? metadata?['triggerId'] as String?;
    return ExecutionRequest(
      id: id ?? _defaultId(source, timestamp),
      source: source,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: metadata == null ? null : Map<String, dynamic>.from(metadata),
      visibility: visibility,
      createdAt: timestamp,
      classification: classification,
      policy: ExecutionPolicy.forRequest(
        mode: classification.mode,
        source: effectiveSource,
        visibility: visibility,
        metadata: metadata,
      ),
      runContext: runId == null
          ? null
          : RunContext(
              runId: runId,
              workflowId: metadata?['workflowId'] as String?,
              resumeToken: metadata?['resumeToken'] as String?,
              waitingReason: metadata?['waitingReason'] as String?,
              waitingMetadata:
                  (metadata?['waitingMetadata'] as Map?)
                      ?.cast<String, Object?>() ??
                  const <String, Object?>{},
              variables:
                  (metadata?['variables'] as Map?)?.cast<String, Object?>() ??
                  const <String, Object?>{},
            ),
    );
  }

  factory ExecutionRequest.fromMcpEvent({
    required String sessionKey,
    required String prompt,
    Map<String, dynamic>? metadata,
    String? id,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.background,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final classification = ExecutionClassifier.classify(
      source: ExecutionSource.mcpEvent,
      metadata: metadata,
    );
    return ExecutionRequest(
      id: id ?? _defaultId(ExecutionSource.mcpEvent, timestamp),
      source: ExecutionSource.mcpEvent,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: metadata == null ? null : Map<String, dynamic>.from(metadata),
      visibility: visibility,
      createdAt: timestamp,
      classification: classification,
      policy: ExecutionPolicy.forRequest(
        mode: classification.mode,
        source: ExecutionSource.mcpEvent,
        visibility: visibility,
        metadata: metadata,
      ),
      runContext: metadata?['runId'] == null
          ? null
          : RunContext(runId: metadata!['runId'] as String),
    );
  }

  factory ExecutionRequest.resume({
    required String sessionKey,
    required String prompt,
    required String runId,
    Map<String, dynamic>? metadata,
    String? id,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.chatAndBackground,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final mergedMetadata = <String, dynamic>{...?metadata, 'runId': runId};
    const classification = ExecutionClassifierOutput(
      mode: ExecutionLifecycleMode.resumeRequest,
      classificationReason: 'resume_signal',
    );
    return ExecutionRequest(
      id: id ?? _defaultId(ExecutionSource.resumeSignal, timestamp),
      source: ExecutionSource.resumeSignal,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: mergedMetadata,
      visibility: visibility,
      createdAt: timestamp,
      classification: classification,
      policy: ExecutionPolicy.forRequest(
        mode: classification.mode,
        source: ExecutionSource.resumeSignal,
        visibility: visibility,
        metadata: mergedMetadata,
      ),
      runContext: RunContext(runId: runId),
    );
  }

  factory ExecutionRequest.persistent({
    required String sessionKey,
    required String prompt,
    Map<String, dynamic>? metadata,
    String? id,
    String? runId,
    DateTime? createdAt,
    ExecutionVisibility visibility = ExecutionVisibility.chatAndBackground,
  }) {
    final timestamp = (createdAt ?? DateTime.now()).toUtc();
    final mergedMetadata = <String, dynamic>{...?metadata};
    if (runId != null) {
      mergedMetadata['runId'] = runId;
    }
    final classification = ExecutionClassifier.classify(
      source: ExecutionSource.system,
      metadata: mergedMetadata,
    );
    return ExecutionRequest(
      id: id ?? _defaultId(ExecutionSource.system, timestamp),
      source: ExecutionSource.system,
      sessionKey: sessionKey,
      prompt: prompt,
      metadata: mergedMetadata.isEmpty ? null : mergedMetadata,
      visibility: visibility,
      createdAt: timestamp,
      classification: classification,
      policy: ExecutionPolicy.forRequest(
        mode: classification.mode,
        source: ExecutionSource.system,
        visibility: visibility,
        metadata: mergedMetadata,
      ),
      runContext: RunContext(
        runId: runId ?? id ?? _defaultId(ExecutionSource.system, timestamp),
        workflowId: mergedMetadata['workflowId'] as String?,
        resumeToken: mergedMetadata['resumeToken'] as String?,
        waitingReason: mergedMetadata['waitingReason'] as String?,
        waitingMetadata:
            (mergedMetadata['waitingMetadata'] as Map?)
                ?.cast<String, Object?>() ??
            const <String, Object?>{},
        variables:
            (mergedMetadata['variables'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }

  static String _defaultId(ExecutionSource source, DateTime timestamp) {
    return '${source.name}_${timestamp.microsecondsSinceEpoch}';
  }
}

class ExecutionClassifier {
  const ExecutionClassifier();

  static ExecutionClassifierOutput classify({
    required ExecutionSource source,
    Map<String, dynamic>? metadata,
  }) {
    if (metadata?['runId'] is String &&
        source == ExecutionSource.resumeSignal) {
      return const ExecutionClassifierOutput(
        mode: ExecutionLifecycleMode.resumeRequest,
        classificationReason: 'resume_signal',
      );
    }
    return switch (source) {
      ExecutionSource.user => const ExecutionClassifierOutput(
        mode: ExecutionLifecycleMode.ephemeralRequest,
        classificationReason: 'chat_user',
      ),
      ExecutionSource.resumeSignal => const ExecutionClassifierOutput(
        mode: ExecutionLifecycleMode.resumeRequest,
        classificationReason: 'resume_signal',
      ),
      ExecutionSource.system => const ExecutionClassifierOutput(
        mode: ExecutionLifecycleMode.persistentRequest,
        classificationReason: 'system_persistent',
      ),
      ExecutionSource.trigger ||
      ExecutionSource.schedule ||
      ExecutionSource.mcpEvent => const ExecutionClassifierOutput(
        mode: ExecutionLifecycleMode.triggeredRequest,
        classificationReason: 'triggered_source',
      ),
    };
  }
}
