import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';

void main() {
  test('approval request is stored and resolved correctly', () async {
    final mailbox = AgentMailbox(idGenerator: () => 'req-1');
    addTearDown(mailbox.dispose);

    final requestFuture = mailbox.approvalRequests.first;
    final decisionFuture = mailbox.requestApproval(
      workerSessionKey: 'agent:main:sub:worker-1',
      call: const ToolCall(id: 'call-1', toolId: 'phone_call'),
    );
    final request = await requestFuture;

    expect(mailbox.pendingApprovals, 1);
    expect(request.requestId, 'req-1');

    final resolved = mailbox.resolve(
      request.requestId,
      const MailboxDecision.approved(),
    );

    expect(resolved, isTrue);
    expect((await decisionFuture).isApproved, isTrue);
    expect(mailbox.pendingApprovals, 0);
  });

  test('rejected decisions propagate back to the requester', () async {
    final mailbox = AgentMailbox(idGenerator: () => 'req-2');
    addTearDown(mailbox.dispose);

    final requestFuture = mailbox.approvalRequests.first;
    final decisionFuture = mailbox.requestApproval(
      workerSessionKey: 'agent:main:sub:worker-2',
      call: const ToolCall(id: 'call-2', toolId: 'sms_send'),
    );
    final request = await requestFuture;
    mailbox.resolve(
      request.requestId,
      const MailboxDecision.rejected(reason: 'user_denied'),
    );

    final decision = await decisionFuture;
    expect(decision.isRejected, isTrue);
    expect(decision.reason, 'user_denied');
  });

  test('duplicate and unknown resolves are handled deterministically', () async {
    final mailbox = AgentMailbox(idGenerator: () => 'same-id');
    addTearDown(mailbox.dispose);

    final requestFuture = mailbox.approvalRequests.first;
    final firstFuture = mailbox.requestApproval(
      workerSessionKey: 'agent:main:sub:worker-3',
      call: const ToolCall(id: 'call-3', toolId: 'screen_lock'),
    );
    final duplicate = await mailbox.requestApproval(
      workerSessionKey: 'agent:main:sub:worker-4',
      call: const ToolCall(id: 'call-4', toolId: 'screen_lock'),
    );
    final request = await requestFuture;

    expect(duplicate.isRejected, isTrue);
    expect(duplicate.reason, 'already_claimed');

    final firstResolved = mailbox.resolve(
      request.requestId,
      const MailboxDecision.approved(),
    );
    final secondResolved = mailbox.resolve(
      request.requestId,
      const MailboxDecision.approved(),
    );
    final unknownResolved = mailbox.resolve(
      'missing',
      const MailboxDecision.rejected(),
    );

    expect(firstResolved, isTrue);
    expect(secondResolved, isFalse);
    expect(unknownResolved, isFalse);
    expect((await firstFuture).isApproved, isTrue);
  });

  test('sub-agent confirmation routes through mailbox while main-agent bypasses it', () async {
    final mailbox = AgentMailbox(idGenerator: () => 'route-1');
    addTearDown(mailbox.dispose);
    var confirmations = 0;

    final router = ToolRouter(
      catalog: InMemoryToolCatalog(
        <ToolDefinition>[
          ToolDefinition(
            id: 'phone_call',
            embedding: const <double>[1],
            requiresConfirmation: true,
            execute: (call) async => const ToolResult.success('dialing'),
          ),
        ],
      ),
      mailbox: mailbox,
      confirmToolCall: (call) async {
        confirmations += 1;
        return true;
      },
    );

    final requestFuture = mailbox.approvalRequests.first;
    final subAgentFuture = router.dispatch(
      const ToolCall(id: 't1', toolId: 'phone_call'),
      sessionKey: 'agent:main:sub:worker-1',
    );
    final request = await requestFuture;
    mailbox.resolve(
      request.requestId,
      const MailboxDecision.approved(),
    );

    final subAgentResult = await subAgentFuture;
    expect(subAgentResult.content, 'dialing');
    expect(confirmations, 0);

    final mainResult = await router.dispatch(
      const ToolCall(id: 't2', toolId: 'phone_call'),
      sessionKey: 'agent:main',
    );

    expect(mainResult.content, 'dialing');
    expect(confirmations, 1);
    expect(mailbox.pendingApprovals, 0);
  });

  test('dispatch validation rejects invalid or over-depth session keys', () async {
    final mailbox = AgentMailbox(
      config: const MailboxDispatchConfig(maxDepth: 2),
      subAgentDispatcher: _Dispatcher(),
    );
    addTearDown(mailbox.dispose);

    final invalid = await mailbox.dispatch(
      const DispatchRequest(
        parentSessionKey: 'bad-key',
        task: 'research task',
      ),
    );
    final tooDeep = await mailbox.dispatch(
      const DispatchRequest(
        parentSessionKey: 'agent:main:sub:a:sub:b',
        task: 'leaf should not spawn',
      ),
    );

    expect(invalid.accepted, isFalse);
    expect(invalid.reason, 'invalid_session_key');
    expect(tooDeep.accepted, isFalse);
    expect(tooDeep.reason, 'max_depth_reached');
  });
}

class _Dispatcher implements SubAgentDispatcher {
  @override
  Future<DispatchResult> dispatch(DispatchRequest request) async {
    return const DispatchResult(
      accepted: true,
      sessionKey: 'agent:main:sub:generated-1',
    );
  }
}
