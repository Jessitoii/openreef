import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';

void main() {
  test(
    'main-agent tool waits for approval and executes after approval',
    () async {
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
      expect(result.status, ToolResultStatus.success);
      expect(result.toolId, 'volume_set');
      expect(result.callId, 'call-1');
      expect(executedCalls, hasLength(1));
    },
  );

  test(
    'main-agent rejection returns rejected result and skips execution',
    () async {
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
      expect(result.status, ToolResultStatus.rejected);
      expect(result.toolId, 'volume_set');
      expect(result.callId, 'call-1');
      expect(result.metadata[ToolRouter.rejectionReasonKey], 'user_rejected');
      expect(executed, isFalse);
    },
  );

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
    expect(result.status, ToolResultStatus.success);
    expect(result.toolId, 'battery_info');
    expect(result.callId, 'call-1');
    expect(confirmCalls, 0);
  });

  test('unknown tool returns normalized unavailable result', () async {
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => true,
    );

    final result = await router.dispatch(
      const ToolCall(id: 'call-missing', toolId: 'missing_tool'),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.unavailable);
    expect(result.toolId, 'missing_tool');
    expect(result.callId, 'call-missing');
    expect(result.metadata['errorCode'], 'unknown_tool:missing_tool');
  });

  test('validation exception maps to normalized validation_error', () async {
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'math_eval',
          embedding: const <double>[1, 0, 0],
          execute: (call) async => throw ArgumentError('bad args'),
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => true,
    );

    final result = await router.dispatch(
      const ToolCall(id: 'call-invalid', toolId: 'math_eval'),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.validationError);
    expect(result.retryable, isFalse);
    expect(result.metadata['errorCode'], 'invalid_arguments');
  });

  test('runtime exception maps to normalized execution_error', () async {
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'explode',
          embedding: const <double>[1, 0, 0],
          execute: (call) async => throw Exception('boom'),
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => true,
    );

    final result = await router.dispatch(
      const ToolCall(id: 'call-boom', toolId: 'explode'),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.executionError);
    expect(result.retryable, isFalse);
    expect(result.metadata['errorCode'], 'execution_error');
  });

  test(
    'hung tool is bounded by router timeout and returns normalized timeout',
    () async {
      final router = ToolRouter(
        catalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'slow',
            embedding: const <double>[1, 0, 0],
            execute: (call) => Completer<ToolResult>().future,
          ),
        ]),
        mailbox: AgentMailbox(),
        confirmToolCall: (call) async => true,
        executionTimeout: const Duration(milliseconds: 20),
      );

      final result = await router.dispatch(
        const ToolCall(id: 'call-slow', toolId: 'slow'),
        sessionKey: 'session-1',
      );

      expect(result.status, ToolResultStatus.timeout);
      expect(result.retryable, isTrue);
      expect(result.toolId, 'slow');
      expect(result.callId, 'call-slow');
    },
  );

  test('unknown serialized status becomes execution_error, not success', () {
    final result = ToolResult.fromMap(const <String, Object?>{
      'status': 'banana',
      'summary': 'bad status',
    });

    expect(result.status, ToolResultStatus.executionError);
    expect(result.metadata['errorCode'], 'invalid_status');
    expect(result.metadata['rawStatus'], 'banana');
  });
}
