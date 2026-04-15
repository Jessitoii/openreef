import 'dart:async';

import 'package:openreef/agent/agent_models.dart';

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

class ApprovalResolution {
  const ApprovalResolution({
    required this.requestId,
    required this.decision,
  });

  final String requestId;
  final MailboxDecision decision;
}

/// AgentMailbox orchestrates dangerous tool approvals from SubAgents.
/// It NO LONGER handles spawning or sub-agent lifecycle management.
class AgentMailbox {
  AgentMailbox({
    String Function()? idGenerator,
    Duration approvalTimeout = const Duration(minutes: 5),
  })  : _idGenerator = idGenerator ?? _defaultIdGenerator,
        _approvalTimeout = approvalTimeout;

  static int _requestSeed = 0;

  final String Function() _idGenerator;
  final Duration _approvalTimeout;
  
  final Map<String, Completer<MailboxDecision>> _pending =
      <String, Completer<MailboxDecision>>{};
  final StreamController<ApprovalRequest> _approvalController =
      StreamController<ApprovalRequest>.broadcast();
  final StreamController<ApprovalResolution> _resolutionController =
      StreamController<ApprovalResolution>.broadcast();
  final Map<String, Timer> _approvalTimers = <String, Timer>{};

  Stream<ApprovalRequest> get approvalRequests => _approvalController.stream;
  Stream<ApprovalResolution> get approvalResolutions => _resolutionController.stream;

  int get pendingApprovals => _pending.length;

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
    _approvalTimers[requestId] = Timer(_approvalTimeout, () {
      resolve(
        requestId,
        const MailboxDecision.rejected(reason: 'timeout'),
      );
    });
    
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
    _approvalTimers.remove(requestId)?.cancel();
    if (completer == null || completer.isCompleted) {
      return false;
    }

    completer.complete(decision);
    _resolutionController.add(
      ApprovalResolution(requestId: requestId, decision: decision),
    );
    return true;
  }

  Future<void> dispose() async {
    for (final timer in _approvalTimers.values) {
      timer.cancel();
    }
    _approvalTimers.clear();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.complete(const MailboxDecision.rejected(reason: 'mailbox_closed'));
      }
    }
    _pending.clear();
    await _approvalController.close();
    await _resolutionController.close();
  }

  static String _defaultIdGenerator() {
    _requestSeed += 1;
    return 'approval_${_requestSeed.toString().padLeft(4, '0')}';
  }
}
