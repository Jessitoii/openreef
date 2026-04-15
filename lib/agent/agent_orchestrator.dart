import 'dart:async';
import 'package:flutter/services.dart';
import 'package:openreef/agent/subagent_runner.dart';

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

class AgentOrchestratorConfig {
  const AgentOrchestratorConfig({
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

abstract class AgentOrchestrator {
  Future<DispatchResult> spawn(DispatchRequest request);
  Future<void> kill(String sessionKey);
  int get activeSubAgentsCount;
  Future<void> dispose();
}

class DefaultAgentOrchestrator implements AgentOrchestrator {
  DefaultAgentOrchestrator({
    AgentOrchestratorConfig config = const AgentOrchestratorConfig(),
    SubAgentRunner runner = const SubAgentRunner(),
  })  : _config = config,
        _runner = runner;

  final AgentOrchestratorConfig _config;
  final SubAgentRunner _runner;
  
  static int _sessionSeed = 0;
  final Map<String, int> _childrenByParent = <String, int>{};
  final Set<String> _activeSessions = <String>{};
  final Map<String, Future<SubAgentRunResult>> _running = <String, Future<SubAgentRunResult>>{};

  @override
  int get activeSubAgentsCount => _activeSessions.length;

  @override
  Future<DispatchResult> spawn(DispatchRequest request) async {
    final validationError = validateDispatch(request.parentSessionKey);
    if (validationError != null) {
      return DispatchResult.rejected(reason: validationError);
    }

    final sessionKey = request.sessionKey ?? _nextSessionKey(request.parentSessionKey);
    
    _reserveDispatch(
      parentSessionKey: request.parentSessionKey,
      sessionKey: sessionKey,
    );

    try {
      final future = _runner.run(
        SubAgentLaunchRequest(
          parentSessionKey: request.parentSessionKey,
          sessionKey: sessionKey,
          task: request.task,
          preferredModel: request.preferredModel,
          timeoutMs: _config.subAgentTimeout.inMilliseconds,
          rootIsolateToken: _rootIsolateToken(),
        ),
      );
      _running[sessionKey] = future;
      
      // ignore: unawaited_futures
      future.whenComplete(() {
        _running.remove(sessionKey);
        _completeDispatch(
          parentSessionKey: request.parentSessionKey,
          sessionKey: sessionKey,
        );
      });
      return DispatchResult(
        accepted: true,
        sessionKey: sessionKey,
      );
    } catch (_) {
      _completeDispatch(
        parentSessionKey: request.parentSessionKey,
        sessionKey: sessionKey,
      );
      return const DispatchResult.rejected(reason: 'dispatch_failed');
    }
  }

  @override
  Future<void> kill(String sessionKey) async {
    // Note: cancellation via sub-agent runner isn't fully supported via isolates out of the box in this simplistic shell, 
    // but we can remove it from active tracking.
    _activeSessions.remove(sessionKey);
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

  bool _completeDispatch({
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

  RootIsolateToken? _rootIsolateToken() {
    try {
      return RootIsolateToken.instance;
    } catch (_) {
      return null;
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
}
