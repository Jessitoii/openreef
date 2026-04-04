import 'dart:async';

import 'package:flutter/services.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/subagent_runner.dart';

enum MailboxDecisionKind {
  approved,
  rejected,
}

class MailboxDecision {
  const MailboxDecision.approved({this.reason})
      : kind = MailboxDecisionKind.approved;

  const MailboxDecision.rejected({this.reason})
      : kind = MailboxDecisionKind.rejected;

  final MailboxDecisionKind kind;
  final String? reason;

  bool get isApproved => kind == MailboxDecisionKind.approved;
  bool get isRejected => kind == MailboxDecisionKind.rejected;
}

class ApprovalRequest {
  const ApprovalRequest({
    required this.requestId,
    required this.workerSessionKey,
    required this.call,
  });

  final String requestId;
  final String workerSessionKey;
  final ToolCall call;
}

class DispatchRequest {
  const DispatchRequest({
    required this.parentSessionKey,
    required this.task,
    this.preferredModel,
    this.sessionKey,
  });

  final String parentSessionKey;
  final String task;
  final String? preferredModel;
  final String? sessionKey;

  DispatchRequest copyWith({
    String? parentSessionKey,
    String? task,
    String? preferredModel,
    String? sessionKey,
  }) {
    return DispatchRequest(
      parentSessionKey: parentSessionKey ?? this.parentSessionKey,
      task: task ?? this.task,
      preferredModel: preferredModel ?? this.preferredModel,
      sessionKey: sessionKey ?? this.sessionKey,
    );
  }
}

class DispatchResult {
  const DispatchResult({
    required this.accepted,
    required this.sessionKey,
    this.reason,
  });

  const DispatchResult.rejected({
    required this.reason,
  })  : accepted = false,
        sessionKey = '';

  final bool accepted;
  final String sessionKey;
  final String? reason;
}

class MailboxDispatchConfig {
  const MailboxDispatchConfig({
    this.maxDepth = 2,
    this.maxChildrenPerAgent = 3,
    this.maxConcurrentSubAgents = 2,
    this.subAgentTimeout = const Duration(minutes: 5),
  });

  final int maxDepth;
  final int maxChildrenPerAgent;
  final int maxConcurrentSubAgents;
  final Duration subAgentTimeout;
}

abstract class SubAgentDispatcher {
  Future<DispatchResult> dispatch(DispatchRequest request);

  Future<void> dispose() async {}
}

class AgentMailbox {
  AgentMailbox({
    String Function()? idGenerator,
    MailboxDispatchConfig config = const MailboxDispatchConfig(),
    SubAgentDispatcher? subAgentDispatcher,
  })  : _idGenerator = idGenerator ?? _defaultIdGenerator,
        _config = config {
    _subAgentDispatcher =
        subAgentDispatcher ??
        _DefaultSubAgentDispatcher(
          timeout: _config.subAgentTimeout,
          onCompleted: completeDispatch,
        );
  }

  static int _requestSeed = 0;
  static int _sessionSeed = 0;

  final String Function() _idGenerator;
  final MailboxDispatchConfig _config;
  late final SubAgentDispatcher _subAgentDispatcher;
  final Map<String, Completer<MailboxDecision>> _pending =
      <String, Completer<MailboxDecision>>{};
  final StreamController<ApprovalRequest> _approvalController =
      StreamController<ApprovalRequest>.broadcast();
  final Map<String, int> _childrenByParent = <String, int>{};
  final Set<String> _activeSessions = <String>{};

  Stream<ApprovalRequest> get approvalRequests => _approvalController.stream;

  int get pendingApprovals => _pending.length;
  int get activeSubAgents => _activeSessions.length;

  Future<MailboxDecision> requestApproval({
    required String workerSessionKey,
    required ToolCall call,
  }) {
    final requestId = _idGenerator();
    if (_pending.containsKey(requestId)) {
      return Future<MailboxDecision>.value(
        const MailboxDecision.rejected(reason: 'already_claimed'),
      );
    }

    final completer = Completer<MailboxDecision>();
    _pending[requestId] = completer;
    _approvalController.add(
      ApprovalRequest(
        requestId: requestId,
        workerSessionKey: workerSessionKey,
        call: call,
      ),
    );
    return completer.future;
  }

  bool resolve(String requestId, MailboxDecision decision) {
    final completer = _pending.remove(requestId);
    if (completer == null || completer.isCompleted) {
      return false;
    }

    completer.complete(decision);
    return true;
  }

  Future<DispatchResult> dispatch(DispatchRequest request) async {
    final validationError = validateDispatch(request.parentSessionKey);
    if (validationError != null) {
      return DispatchResult.rejected(reason: validationError);
    }

    final sessionKey = request.sessionKey ?? _nextSessionKey(request.parentSessionKey);
    _reserveDispatch(
      parentSessionKey: request.parentSessionKey,
      sessionKey: sessionKey,
    );

    final result = await _subAgentDispatcher.dispatch(
      request.copyWith(sessionKey: sessionKey),
    );
    if (!result.accepted) {
      completeDispatch(
        parentSessionKey: request.parentSessionKey,
        sessionKey: sessionKey,
      );
      return result;
    }

    if (result.sessionKey != sessionKey) {
      _activeSessions.remove(sessionKey);
      _activeSessions.add(result.sessionKey);
    }

    return result;
  }

  String? validateDispatch(String sessionKey) {
    final depth = _depthOf(sessionKey);
    if (depth == null) {
      return 'invalid_session_key';
    }
    if (depth >= _config.maxDepth) {
      return 'max_depth_reached';
    }
    if (_activeSessions.length >= _config.maxConcurrentSubAgents) {
      return 'max_concurrent_sub_agents';
    }
    final children = _childrenByParent[sessionKey] ?? 0;
    if (children >= _config.maxChildrenPerAgent) {
      return 'max_children_reached';
    }
    return null;
  }

  bool completeDispatch({
    required String parentSessionKey,
    required String sessionKey,
  }) {
    final removed = _activeSessions.remove(sessionKey);
    if (!removed) {
      return false;
    }

    final children = _childrenByParent[parentSessionKey];
    if (children == null || children <= 1) {
      _childrenByParent.remove(parentSessionKey);
    } else {
      _childrenByParent[parentSessionKey] = children - 1;
    }
    return true;
  }

  Future<void> dispose() async {
    await _subAgentDispatcher.dispose();
    await _approvalController.close();
  }

  static String _defaultIdGenerator() {
    _requestSeed += 1;
    return 'approval_${_requestSeed.toString().padLeft(4, '0')}';
  }

  void _reserveDispatch({
    required String parentSessionKey,
    required String sessionKey,
  }) {
    _activeSessions.add(sessionKey);
    _childrenByParent.update(
      parentSessionKey,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  static String _nextSessionKey(String parentSessionKey) {
    _sessionSeed += 1;
    final suffix = _sessionSeed.toString().padLeft(4, '0');
    return '$parentSessionKey:sub:$suffix';
  }

  static int? _depthOf(String sessionKey) {
    if (sessionKey == 'agent:main') {
      return 0;
    }

    final segments = sessionKey.split(':');
    if (segments.length < 4 || segments[0] != 'agent' || segments[1] != 'main') {
      return null;
    }

    for (var index = 2; index < segments.length; index += 2) {
      if (segments[index] != 'sub') {
        return null;
      }
      if (index + 1 >= segments.length || segments[index + 1].isEmpty) {
        return null;
      }
    }

    return (segments.length - 2) ~/ 2;
  }
}

class _DefaultSubAgentDispatcher implements SubAgentDispatcher {
  _DefaultSubAgentDispatcher({
    required Duration timeout,
    required this.onCompleted,
    SubAgentRunner runner = const SubAgentRunner(),
  })  : _timeout = timeout,
        _runner = runner;

  final Duration _timeout;
  final SubAgentRunner _runner;
  final bool Function({
    required String parentSessionKey,
    required String sessionKey,
  }) onCompleted;
  final Map<String, Future<SubAgentRunResult>> _running =
      <String, Future<SubAgentRunResult>>{};

  @override
  Future<DispatchResult> dispatch(DispatchRequest request) async {
    final sessionKey = request.sessionKey;
    if (sessionKey == null || sessionKey.isEmpty) {
      return const DispatchResult.rejected(reason: 'dispatcher_unavailable');
    }

    try {
      final future = _runner.run(
        SubAgentLaunchRequest(
          parentSessionKey: request.parentSessionKey,
          sessionKey: sessionKey,
          task: request.task,
          preferredModel: request.preferredModel,
          timeoutMs: _timeout.inMilliseconds,
          rootIsolateToken: _rootIsolateToken(),
        ),
      );
      _running[sessionKey] = future;
      unawaited(
        future.whenComplete(() {
          _running.remove(sessionKey);
          onCompleted(
            parentSessionKey: request.parentSessionKey,
            sessionKey: sessionKey,
          );
        }),
      );
      return DispatchResult(
        accepted: true,
        sessionKey: sessionKey,
      );
    } catch (_) {
      return const DispatchResult.rejected(reason: 'dispatch_failed');
    }
  }

  @override
  Future<void> dispose() async {
    await Future.wait<void>(
      _running.values.map(
        (future) => future.then<void>((_) {}).catchError((_) {}),
      ),
    );
    _running.clear();
  }

  RootIsolateToken? _rootIsolateToken() {
    try {
      return RootIsolateToken.instance;
    } catch (_) {
      return null;
    }
  }
}
