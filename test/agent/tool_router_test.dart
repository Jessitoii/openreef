import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/tools/ddgs_web_search_service.dart';
import 'package:openreef/tools/mvp_native_tools.dart';
import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/tools/system_native_tools.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_manifest_bridge.dart';
import 'package:openreef/tools/tool_manifest_registry.dart';

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
            argumentSchema: const <ToolArgumentSpec>[
              ToolArgumentSpec(
                name: 'level',
                type: ToolArgumentType.doubleValue,
              ),
            ],
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

  test('cancellation while waiting for approval returns cancelled', () async {
    var executed = false;
    final approvalCompleter = Completer<bool>();
    final cancellation = CancellationSignal();
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'sms_send',
          embedding: const <double>[1, 0, 0],
          requiresConfirmation: true,
          execute: (call) async {
            executed = true;
            return const ToolResult.success('sent');
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) => approvalCompleter.future,
    );

    final resultFuture = router.dispatch(
      const ToolCall(id: 'call-approval', toolId: 'sms_send'),
      sessionKey: 'session-1',
      cancellationSignal: cancellation,
    );

    await Future<void>.delayed(Duration.zero);
    cancellation.cancel(RunCancellationReason.userRequested.code);
    final result = await resultFuture;

    expect(result.status, ToolResultStatus.cancelled);
    expect(result.metadata['reason'], 'user_requested');
    expect(executed, isFalse);
  });

  test('cancellation while tool executes discards late result', () async {
    final toolCompleter = Completer<ToolResult>();
    final cancellation = CancellationSignal();
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0],
          execute: (call) => toolCompleter.future,
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => true,
    );

    final resultFuture = router.dispatch(
      const ToolCall(id: 'call-tool', toolId: 'battery_info'),
      sessionKey: 'session-1',
      cancellationSignal: cancellation,
    );

    await Future<void>.delayed(Duration.zero);
    cancellation.cancel(RunCancellationReason.userRequested.code);
    toolCompleter.complete(const ToolResult.success('late success'));
    final result = await resultFuture;

    expect(result.status, ToolResultStatus.cancelled);
    expect(result.content, isNot('late success'));
  });

  test('malformed request never reaches approval or execution', () async {
    var confirmCalls = 0;
    var executed = false;
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'sms_draft',
          embedding: const <double>[1, 0, 0],
          requiresConfirmation: true,
          argumentSchema: const <ToolArgumentSpec>[
            ToolArgumentSpec(name: 'recipient', type: ToolArgumentType.string),
            ToolArgumentSpec(name: 'body', type: ToolArgumentType.string),
          ],
          execute: (call) async {
            executed = true;
            return const ToolResult.success('created');
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async {
        confirmCalls += 1;
        return true;
      },
    );

    final result = await router.dispatch(
      const ToolCall(
        id: 'call-bad',
        toolId: 'sms_draft',
        rawArguments: 'not-json',
        hasRawArguments: true,
      ),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.validationError);
    expect(result.metadata['reason'], 'malformed_tool_call');
    expect(confirmCalls, 0);
    expect(executed, isFalse);
  });

  test('schema wrapper never reaches approval or execution', () async {
    var confirmCalls = 0;
    var executed = false;
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'sms_draft',
          embedding: const <double>[1, 0, 0],
          requiresConfirmation: true,
          argumentSchema: const <ToolArgumentSpec>[
            ToolArgumentSpec(name: 'recipient', type: ToolArgumentType.string),
            ToolArgumentSpec(name: 'body', type: ToolArgumentType.string),
          ],
          execute: (call) async {
            executed = true;
            return const ToolResult.success('created');
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async {
        confirmCalls += 1;
        return true;
      },
    );

    final result = await router.dispatch(
      const ToolCall(
        id: 'call-schema',
        toolId: 'sms_draft',
        arguments: <String, Object?>{
          'parameters': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        },
        rawArguments: <String, Object?>{
          'parameters': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
          },
        },
        hasRawArguments: true,
      ),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.validationError);
    expect(result.metadata['reason'], 'schema_passed_as_args');
    expect(confirmCalls, 0);
    expect(executed, isFalse);
  });

  test('protocol tokens in args never reach approval or execution', () async {
    var confirmCalls = 0;
    var executed = false;
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'sms_draft',
          embedding: const <double>[1, 0, 0],
          requiresConfirmation: true,
          argumentSchema: const <ToolArgumentSpec>[
            ToolArgumentSpec(name: 'recipient', type: ToolArgumentType.string),
            ToolArgumentSpec(name: 'body', type: ToolArgumentType.string),
          ],
          execute: (call) async {
            executed = true;
            return const ToolResult.success('created');
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async {
        confirmCalls += 1;
        return true;
      },
    );

    final result = await router.dispatch(
      const ToolCall(
        id: 'call-leak',
        toolId: 'sms_draft',
        arguments: <String, Object?>{
          'recipient': '5550100',
          'body': '<|assistant|> leaked token',
        },
        rawArguments: <String, Object?>{
          'recipient': '5550100',
          'body': '<|assistant|> leaked token',
        },
        hasRawArguments: true,
      ),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.validationError);
    expect(result.metadata['reason'], 'malformed_tool_call');
    expect(confirmCalls, 0);
    expect(executed, isFalse);
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

  test('typed tool-call source is preserved through normalization', () async {
    late ToolCall executedCall;
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0],
          execute: (call) async {
            executedCall = call;
            return const ToolResult.success('ok');
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => true,
    );

    final result = await router.dispatch(
      const ToolCall(
        id: 'typed-1',
        toolId: 'battery_info',
        source: ToolCallSource.flutterGemmaTyped,
      ),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.success);
    expect(executedCall.source, ToolCallSource.flutterGemmaTyped);
  });

  test(
    'parsed protocol tool-call source is preserved through normalization',
    () async {
      late ToolCall executedCall;
      final router = ToolRouter(
        catalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0],
            execute: (call) async {
              executedCall = call;
              return const ToolResult.success('ok');
            },
          ),
        ]),
        mailbox: AgentMailbox(),
        confirmToolCall: (call) async => true,
      );

      final parsed = const AgentResponseParser().parse(
        '{"tool_call":{"id":"parsed-1","tool_id":"battery_info","arguments":{}}}',
      );
      final result = await router.dispatch(
        parsed.effectiveToolCalls.single,
        sessionKey: 'session-1',
      );

      expect(result.status, ToolResultStatus.success);
      expect(executedCall.source, ToolCallSource.textParsed);
    },
  );

  test(
    'production-style confirmation-required native tool reaches approval',
    () async {
      final volumeAdapter = _RecordingVolumeAdapter();
      final router = _nativeRouterFor(<NativeToolHandler>[
        VolumeSetToolHandler(volumeAdapter),
      ]);
      final result = await router.dispatch(
        const ToolCall(
          id: 'call-volume',
          toolId: 'volume_set',
          arguments: <String, Object?>{'level': 0.25},
        ),
        sessionKey: 'session-1',
      );

      expect(result.status, ToolResultStatus.success);
      expect(volumeAdapter.lastLevel, 0.25);
    },
  );

  test('normalizes Bluetooth on before native validation', () async {
    late ToolCall approvedCall;
    final router = _nativeRouterFor(
      <NativeToolHandler>[BluetoothToggleToolHandler()],
      confirmToolCall: (call) async {
        approvedCall = call;
        return true;
      },
    );

    final result = await router.dispatch(
      const ToolCall(id: 'call-bluetooth', toolId: 'bluetooth_toggle'),
      sessionKey: 'session-1',
      userMessage: 'set my Bluetooth on',
    );

    expect(result.status, ToolResultStatus.unavailable);
    expect(result.summary, 'bluetooth_toggle_platform_restricted');
    expect(approvedCall.arguments['enabled'], isTrue);
  });

  test('normalizes Bluetooth off before native validation', () async {
    late ToolCall approvedCall;
    final router = _nativeRouterFor(
      <NativeToolHandler>[BluetoothToggleToolHandler()],
      confirmToolCall: (call) async {
        approvedCall = call;
        return true;
      },
    );

    final result = await router.dispatch(
      const ToolCall(id: 'call-bluetooth', toolId: 'bluetooth_toggle'),
      sessionKey: 'session-1',
      userMessage: 'turn Bluetooth off',
    );

    expect(result.status, ToolResultStatus.unavailable);
    expect(result.summary, 'bluetooth_toggle_platform_restricted');
    expect(approvedCall.arguments['enabled'], isFalse);
  });

  test('normalizes max volume before native validation', () async {
    final volumeAdapter = _RecordingVolumeAdapter();
    final router = _nativeRouterFor(<NativeToolHandler>[
      VolumeSetToolHandler(volumeAdapter),
    ]);

    final result = await router.dispatch(
      const ToolCall(id: 'call-volume', toolId: 'volume_set'),
      sessionKey: 'session-1',
      userMessage: 'turn the volume all the way up',
    );

    expect(result.status, ToolResultStatus.success);
    expect(volumeAdapter.lastLevel, 1);
  });

  test(
    'missing required argument does not expose raw validation payload',
    () async {
      final router = _nativeRouterFor(<NativeToolHandler>[
        BluetoothToggleToolHandler(),
      ]);

      final result = await router.dispatch(
        const ToolCall(id: 'call-bluetooth', toolId: 'bluetooth_toggle'),
        sessionKey: 'session-1',
        userMessage: 'bluetooth',
      );

      expect(result.status, ToolResultStatus.validationError);
      expect(result.summary, 'missing_argument:enabled');
      expect(result.userVisibleMessage, isNot(contains('missing_argument')));
      expect(result.userVisibleMessage, isNot(contains('enabled')));
    },
  );

  test(
    'production-style no-confirmation native tool bypasses approval',
    () async {
      var confirmCalls = 0;
      final router = _nativeRouterFor(
        <NativeToolHandler>[BatteryInfoToolHandler(_FixedBatteryAdapter())],
        confirmToolCall: (call) async {
          confirmCalls += 1;
          return true;
        },
      );

      final result = await router.dispatch(
        const ToolCall(id: 'call-battery', toolId: 'battery_info'),
        sessionKey: 'session-1',
      );

      expect(result.status, ToolResultStatus.success);
      expect(confirmCalls, 0);
    },
  );

  test('production-style optional args accept omitted optional key', () async {
    final shareAdapter = _RecordingShareAdapter();
    final router = _nativeRouterFor(<NativeToolHandler>[
      ShareToolHandler(shareAdapter),
    ]);

    final result = await router.dispatch(
      const ToolCall(
        id: 'call-share',
        toolId: 'share',
        arguments: <String, Object?>{'text': 'reef'},
      ),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.success);
    expect(shareAdapter.lastText, 'reef');
    expect(shareAdapter.lastSubject, isNull);
  });

  test('production-style multi-key map args route through execution', () async {
    final notificationAdapter = _RecordingNotificationAdapter();
    final router = _nativeRouterFor(<NativeToolHandler>[
      NotifyToolHandler(notificationAdapter),
    ]);

    final result = await router.dispatch(
      const ToolCall(
        id: 'call-notify',
        toolId: 'notify',
        arguments: <String, Object?>{
          'title': 'OpenReef',
          'body': 'Tool routed',
        },
      ),
      sessionKey: 'session-1',
    );

    expect(result.status, ToolResultStatus.success);
    expect(notificationAdapter.lastTitle, 'OpenReef');
    expect(notificationAdapter.lastBody, 'Tool routed');
  });

  test(
    'production-style runtime failure after routing is execution_error',
    () async {
      final router = _nativeRouterFor(<NativeToolHandler>[
        FileReadToolHandler(),
      ]);

      final result = await router.dispatch(
        ToolCall(
          id: 'call-file',
          toolId: 'file_read',
          arguments: <String, Object?>{
            'path':
                '${Directory.systemTemp.path}${Platform.pathSeparator}openreef_missing_file.txt',
          },
        ),
        sessionKey: 'session-1',
      );

      expect(result.status, ToolResultStatus.executionError);
      expect(result.metadata['errorCode'], 'native_error');
    },
  );

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

  test('legacy communication ids are routed to canonical tools only', () async {
    final executedToolIds = <String>[];
    final router = ToolRouter(
      catalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'sms_send',
          embedding: const <double>[1, 0, 0],
          execute: (call) async {
            executedToolIds.add(call.toolId);
            return ToolResult.success(
              'sent',
              toolId: call.toolId,
              callId: call.id,
            );
          },
        ),
        ToolDefinition(
          id: 'phone_call',
          embedding: const <double>[1, 0, 0],
          execute: (call) async {
            executedToolIds.add(call.toolId);
            return ToolResult.success(
              'called',
              toolId: call.toolId,
              callId: call.id,
            );
          },
        ),
        ToolDefinition(
          id: 'phone_dial',
          embedding: const <double>[1, 0, 0],
          execute: (call) async {
            executedToolIds.add(call.toolId);
            return ToolResult.success(
              'dialed',
              toolId: call.toolId,
              callId: call.id,
            );
          },
        ),
      ]),
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => true,
    );

    final sms = await router.dispatch(
      const ToolCall(id: 'old-sms', toolId: 'communication_sms_send'),
      sessionKey: 'session-1',
    );
    final call = await router.dispatch(
      const ToolCall(id: 'old-call', toolId: 'communication_phone_call'),
      sessionKey: 'session-1',
    );
    final dial = await router.dispatch(
      const ToolCall(id: 'old-dial', toolId: 'communication_phone_dial'),
      sessionKey: 'session-1',
    );

    expect(sms.toolId, 'sms_send');
    expect(call.toolId, 'phone_call');
    expect(dial.toolId, 'phone_dial');
    expect(executedToolIds, <String>['sms_send', 'phone_call', 'phone_dial']);
  });

  test('DDGS stub backend reports web search as unavailable', () async {
    final router = _nativeRouterFor(<NativeToolHandler>[
      WebSearchToolHandler(DdgsWebSearchService()),
      WebFetchToolHandler(DdgsWebSearchService()),
    ]);

    final searchResult = await router.dispatch(
      const ToolCall(
        id: 'search-1',
        toolId: 'web_search',
        arguments: <String, Object?>{'query': 'openreef'},
      ),
      sessionKey: 'session-1',
    );
    final fetchResult = await router.dispatch(
      const ToolCall(
        id: 'fetch-1',
        toolId: 'web_fetch',
        arguments: <String, Object?>{'url': 'https://example.com'},
      ),
      sessionKey: 'session-1',
    );

    expect(searchResult.status, ToolResultStatus.unavailable);
    expect(searchResult.summary, DdgsWebSearchService.searchUnavailableMessage);
    expect(fetchResult.status, ToolResultStatus.unavailable);
    expect(fetchResult.summary, DdgsWebSearchService.fetchUnavailableMessage);
  });
}

ToolRouter _nativeRouterFor(
  List<NativeToolHandler> handlers, {
  Future<bool> Function(ToolCall call)? confirmToolCall,
}) {
  final registry = ToolManifestRegistry(handlers);
  final bridge = ToolManifestBridge(registry);
  final tools = handlers
      .map(
        (handler) => bridge.toToolDefinition(
          toolId: handler.manifest.id,
          embedding: const <double>[1, 0, 0],
        ),
      )
      .toList(growable: false);
  return ToolRouter(
    catalog: InMemoryToolCatalog(tools),
    mailbox: AgentMailbox(),
    confirmToolCall: confirmToolCall ?? (call) async => true,
  );
}

class _RecordingVolumeAdapter implements DeviceVolumeAdapter {
  double? lastLevel;

  @override
  Future<double> setVolumeLevel(double normalizedLevel) async {
    lastLevel = normalizedLevel;
    return normalizedLevel;
  }
}

class _FixedBatteryAdapter implements BatteryAdapter {
  @override
  Future<BatterySnapshot> readBatteryInfo() async {
    return const BatterySnapshot(level: 72, state: BatteryState.charging);
  }
}

class _RecordingShareAdapter implements ShareAdapter {
  String? lastText;
  String? lastSubject;

  @override
  Future<void> shareText({required String text, String? subject}) async {
    lastText = text;
    lastSubject = subject;
  }
}

class _RecordingNotificationAdapter implements NotificationAdapter {
  String? lastTitle;
  String? lastBody;

  @override
  Future<NotificationDispatch> showNotification({
    required String title,
    required String body,
  }) async {
    lastTitle = title;
    lastBody = body;
    return NotificationDispatch(
      notificationId: 1,
      dispatchedAt: DateTime.utc(2026, 4, 19),
    );
  }
}
