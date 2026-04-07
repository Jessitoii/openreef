import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';

void main() {
  test('main-agent tool waits for approval and executes after approval', () async {
    final executedCalls = <ToolCall>[];
    final approvalCompleter = Completer<bool>();
    final requestedCalls = <ToolCall>[];
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'volume_set',
          embedding: const <double>[1, 0, 0],
          requiresConfirmation: true,
          execute: (call) async {
            executedCalls.add(call);
            return const ToolResult.success('approved');
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) {
        requestedCalls.add(call);
        return approvalCompleter.future;
      },
    );

    final resultFuture = router.dispatch(
      const ToolCall(
        id: 'call-1',
        toolId: 'volume_set',
        arguments: <String, Object?>{'level': 0.5},
      ),
      sessionKey: 'session-1',
    );

    await Future<void>.delayed(Duration.zero);
    expect(requestedCalls, hasLength(1));
    expect(executedCalls, isEmpty);

    approvalCompleter.complete(true);
    final result = await resultFuture;

    expect(result.content, 'approved');
    expect(executedCalls, hasLength(1));
  });

  test('main-agent rejection returns rejected result and skips execution', () async {
    var executed = false;
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'volume_set',
          embedding: const <double>[1, 0, 0],
          requiresConfirmation: true,
          execute: (call) async {
            executed = true;
            return const ToolResult.success('approved');
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => false,
    );

    final result = await router.dispatch(
      const ToolCall(id: 'call-1', toolId: 'volume_set'),
      sessionKey: 'session-1',
    );

    expect(result.isRejected, isTrue);
    expect(
      result.metadata[ToolRouter.rejectionReasonKey],
      'user_rejected',
    );
    expect(executed, isFalse);
  });

  test('non-sensitive tools bypass approval', () async {
    var confirmCalls = 0;
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0],
          execute: (call) async => const ToolResult.success('ok'),
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async {
        confirmCalls += 1;
        return true;
      },
    );

    final result = await router.dispatch(
      const ToolCall(id: 'call-1', toolId: 'battery_info'),
      sessionKey: 'session-1',
    );

    expect(result.content, 'ok');
    expect(confirmCalls, 0);
  });
}
