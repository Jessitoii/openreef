import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_notifier.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/runtime_transcript_event.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_formation_service.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late MemoryIndex memoryIndex;
  late MemoryFormer memoryFormer;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    memoryIndex = MemoryIndex(storage);
    memoryFormer = MemoryFormer(
      storage: storage,
      memoryIndex: memoryIndex,
      embedder: const _FixedSemanticEmbedder(<double>[1, 0, 0]),
    );
  });

  tearDown(() async {
    await storage.close();
  });

  test('repeated rejected same request does not loop forever', () async {
    final notifier = _RecordingNotifier();
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: _QueueModelAdapter(<AgentResponse>[
        const AgentResponse(
          text: 'please ask again',
          toolCall: ToolCall(id: '1', toolId: 'volume_set'),
        ),
        const AgentResponse(
          text: 'retrying',
          toolCall: ToolCall(id: '2', toolId: 'volume_set'),
        ),
        const AgentResponse(
          text: 'still retrying',
          toolCall: ToolCall(id: '3', toolId: 'volume_set'),
        ),
        const AgentResponse(
          text: 'would have continued',
          toolCall: ToolCall(id: '4', toolId: 'volume_set'),
        ),
      ]),
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'session_status',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'memory_search',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'notify',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'volume_set',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          argumentSchema: const <ToolArgumentSpec>[
            ToolArgumentSpec(name: 'level', type: ToolArgumentType.integer),
          ],
          requiresConfirmation: true,
          execute: _okExecute,
        ),
      ]),
      notifier: notifier,
      confirmToolCall: (call) async => false,
    );

    final result = await loop.run(
      'trigger rejection loop',
      sessionKey: 'agent:main',
    );

    expect(result.sessionResult, SessionResult.frozen);
    expect(result.reason, 'rejection_loop');
    expect(result.toolsUsed, const <String>[
      'volume_set',
      'volume_set',
      'volume_set',
    ]);
    expect(
      result.toolResults.map((toolResult) => toolResult.status),
      everyElement(ToolResultStatus.rejected),
    );
    expect(notifier.freezeCalls, 1);
  });

  test(
    'repeated thrown failure of same blocked class freezes deterministically',
    () async {
      final notifier = _RecordingNotifier();
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: _QueueModelAdapter(<AgentResponse>[
          const AgentResponse(
            text: '',
            toolCall: ToolCall(id: '1', toolId: 'explode'),
          ),
          const AgentResponse(
            text: '',
            toolCall: ToolCall(id: '2', toolId: 'explode'),
          ),
          const AgentResponse(
            text: '',
            toolCall: ToolCall(id: '3', toolId: 'explode'),
          ),
          const AgentResponse(
            text: '',
            toolCall: ToolCall(id: '4', toolId: 'explode'),
          ),
        ]),
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'session_status',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'memory_search',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'notify',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'explode',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _failingExecute,
          ),
        ]),
        notifier: notifier,
      );

      final result = await loop.run(
        'trigger failures',
        sessionKey: 'agent:main',
      );

      expect(result.sessionResult, SessionResult.frozen);
      expect(result.reason, 'exception_loop');
      expect(result.toolsUsed, const <String>['explode', 'explode', 'explode']);
      expect(
        result.toolResults.map((toolResult) => toolResult.status),
        everyElement(ToolResultStatus.executionError),
      );
      expect(notifier.freezeCalls, 1);
    },
  );

  test('successful tool execution resets no-progress tracking', () async {
    final notifier = _RecordingNotifier();
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: _QueueModelAdapter(<AgentResponse>[
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: '1', toolId: 'volume_set'),
        ),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(
            id: '2',
            toolId: 'volume_set',
            arguments: <String, Object?>{'level': 2},
          ),
        ),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: '3', toolId: 'recover'),
        ),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: '4', toolId: 'volume_set'),
        ),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: '5', toolId: 'volume_set'),
        ),
        const AgentResponse(text: 'done'),
      ]),
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'session_status',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'memory_search',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'notify',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'volume_set',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          argumentSchema: const <ToolArgumentSpec>[
            ToolArgumentSpec(name: 'level', type: ToolArgumentType.integer),
          ],
          requiresConfirmation: true,
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'recover',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
      ]),
      notifier: notifier,
      confirmToolCall: (call) async => call.toolId == 'recover',
    );

    final result = await loop.run(
      'recover after blocked attempts',
      sessionKey: 'agent:main',
    );

    expect(result.sessionResult, SessionResult.completed);
    expect(result.text, 'done');
    expect(
      result.toolResults.map((toolResult) => toolResult.status),
      <ToolResultStatus>[
        ToolResultStatus.rejected,
        ToolResultStatus.rejected,
        ToolResultStatus.success,
        ToolResultStatus.rejected,
        ToolResultStatus.rejected,
      ],
    );
    expect(result.toolsUsed, const <String>[
      'volume_set',
      'volume_set',
      'recover',
      'volume_set',
      'volume_set',
    ]);
    expect(notifier.freezeCalls, 0);
  });

  test(
    'parallel structured tool calls dispatch sequentially through router',
    () async {
      final notifier = _RecordingNotifier();
      final executed = <String>[];
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: _QueueModelAdapter(<AgentResponse>[
          const AgentResponse(
            text: '',
            toolCalls: <ToolCall>[
              ToolCall(id: '1', toolId: 'first'),
              ToolCall(id: '2', toolId: 'second'),
            ],
          ),
          const AgentResponse(text: 'done'),
        ]),
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'session_status',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'memory_search',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'notify',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'first',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async {
              executed.add(call.toolId);
              return const ToolResult.success('first ok');
            },
          ),
          ToolDefinition(
            id: 'second',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async {
              executed.add(call.toolId);
              return const ToolResult.success('second ok');
            },
          ),
        ]),
        notifier: notifier,
      );

      final result = await loop.run('run two tools', sessionKey: 'agent:main');

      expect(result.sessionResult, SessionResult.completed);
      expect(executed, const <String>['first', 'second']);
      expect(result.toolsUsed, const <String>['first', 'second']);
      expect(result.toolResults, hasLength(2));
      expect(
        result.toolResults.map((toolResult) => toolResult.status),
        everyElement(ToolResultStatus.success),
      );
    },
  );

  test(
    'tool-call protocol output is not emitted as assistant transcript',
    () async {
      final sink = _RecordingTranscriptSink();
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: _QueueModelAdapter(<AgentResponse>[
          const AgentResponse(
            text: '',
            rawOutput:
                '{"tool_call":{"id":"call-1","tool_id":"battery_info","arguments":{}}}',
            toolCall: ToolCall(id: 'call-1', toolId: 'battery_info'),
          ),
          const AgentResponse(text: 'Battery is available.'),
        ]),
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
        ]),
        notifier: _RecordingNotifier(),
      );

      final result = await loop.run(
        'check battery',
        sessionKey: 'agent:main',
        transcriptSink: sink,
        requestId: 'request-json',
      );

      expect(result.text, 'Battery is available.');
      expect(
        sink.events
            .where(
              (event) =>
                  event.kind ==
                  RuntimeTranscriptEventKind.assistantMessageDelta,
            )
            .map((event) => event.deltaText)
            .join(),
        isNot(contains('tool_call')),
      );
      expect(
        sink.events.map((event) => event.kind),
        contains(RuntimeTranscriptEventKind.toolStepStarted),
      );
    },
  );

  test(
    'raw flutter_gemma tool marker dispatches instead of persisting',
    () async {
      final sink = _RecordingTranscriptSink();
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: _StreamingQueueAdapter(<String>[
          '<|tool_call>call:battery_info{}<tool_call|>',
          'Battery is available.',
        ]),
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
        ]),
        notifier: _RecordingNotifier(),
      );

      final result = await loop.run(
        'check battery',
        sessionKey: 'agent:main',
        transcriptSink: sink,
        requestId: 'request-marker',
      );

      expect(result.sessionResult, SessionResult.completed);
      expect(result.text, 'Battery is available.');
      expect(result.toolsUsed, const <String>['battery_info']);
      expect(result.text, isNot(contains('<|tool_call>')));
      expect(
        sink.events
            .where(
              (event) =>
                  event.kind ==
                  RuntimeTranscriptEventKind.assistantMessageDelta,
            )
            .map((event) => event.deltaText)
            .join(),
        allOf(isNot(contains('<|tool_call>')), isNot(contains('tool_call'))),
      );
    },
  );

  test(
    'malformed tool generation is internal and skips transcript and memory',
    () async {
      final sink = _RecordingTranscriptSink();
      final memoryFormation = _RecordingMemoryFormationService();
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        memoryFormationService: memoryFormation,
        modelAdapter: _StreamingQueueAdapter(<String>[
          '<|tool_call>call:battery_info{"bad"<tool_call|>',
          'Recovered text should stay internal.',
        ]),
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
        ]),
        notifier: _RecordingNotifier(),
      );

      final result = await loop.run(
        'check battery',
        sessionKey: 'agent:main',
        transcriptSink: sink,
        requestId: 'request-malformed-marker',
      );

      expect(result.sessionResult, SessionResult.completed);
      expect(result.text, 'Recovered text should stay internal.');
      expect(
        result.toolResults.single.status,
        ToolResultStatus.validationError,
      );
      expect(
        result.toolResults.single.metadata['reason'],
        'malformed_tool_call',
      );
      expect(result.toolResults.single.metadata['visibleSuppressed'], isTrue);
      expect(memoryFormation.turns, isEmpty);
      expect(
        sink.events
            .where(
              (event) =>
                  event.kind ==
                  RuntimeTranscriptEventKind.assistantMessageDelta,
            )
            .map((event) => event.deltaText)
            .join(),
        isEmpty,
      );
    },
  );

  test('typed battery tool call appends result and continues once', () async {
    var dispatchCount = 0;
    final memoryFormation = _RecordingMemoryFormationService();
    final adapter = _TypedToolAdapter(
      initialResponse: const AgentResponse(
        text: '',
        toolCalls: <ToolCall>[
          ToolCall(
            id: 'call-1',
            toolId: 'battery_info',
            rawArguments: <String, Object?>{},
            hasRawArguments: true,
          ),
        ],
        toolCallSource: ToolCallSource.flutterGemmaTyped,
      ),
      continuationResponse: const AgentResponse(text: 'Battery is available.'),
    );
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: adapter,
      memoryFormationService: memoryFormation,
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: (call) async {
            dispatchCount += 1;
            return const ToolResult.success('battery ok');
          },
        ),
      ]),
      notifier: _RecordingNotifier(),
    );

    final result = await loop.run(
      'can you check my battery?',
      sessionKey: 'agent:main',
    );

    expect(result.sessionResult, SessionResult.completed);
    expect(result.text, 'Battery is available.');
    expect(dispatchCount, 1);
    expect(adapter.appendedToolNames, const <String>['battery_info']);
    expect(adapter.continuationCalls, 1);
    expect(result.toolsUsed, const <String>['battery_info']);
    expect(memoryFormation.turns, hasLength(1));
    expect(
      memoryFormation.turns.single.assistantMessage,
      'Battery is available.',
    );
    expect(
      memoryFormation.turns.single.toolOutputs
          .map((message) => message.content)
          .join('\n'),
      isNot(contains('tool_call')),
    );
  });

  test('schema-shaped typed args re-enter loop before dispatch', () async {
    var dispatchCount = 0;
    final adapter = _TypedToolAdapter(
      initialResponse: const AgentResponse(
        text: '',
        toolCalls: <ToolCall>[
          ToolCall(
            id: 'call-1',
            toolId: 'battery_info',
            arguments: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            },
            rawArguments: <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{},
            },
            hasRawArguments: true,
          ),
        ],
        toolCallSource: ToolCallSource.flutterGemmaTyped,
      ),
      continuationResponse: const AgentResponse(
        text: 'I tried to check battery info, but the tool call was malformed.',
      ),
    );
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: adapter,
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: (call) async {
            dispatchCount += 1;
            return const ToolResult.success('battery ok');
          },
        ),
      ]),
      notifier: _RecordingNotifier(),
    );

    final result = await loop.run(
      'can you check my battery?',
      sessionKey: 'agent:main',
    );

    expect(result.sessionResult, SessionResult.completed);
    expect(
      result.text,
      'I tried to check battery info, but the tool call was malformed.',
    );
    expect(dispatchCount, 0);
    expect(adapter.appendedToolNames, const <String>['battery_info']);
    expect(adapter.continuationCalls, 1);
    expect(result.toolResults.single.status, ToolResultStatus.validationError);
    expect(
      result.toolResults.single.metadata['reason'],
      'schema_passed_as_args',
    );
  });

  test('non-map typed args re-enter loop before dispatch', () async {
    for (final rawArgs in <Object?>[null, const <Object?>[], 'oops']) {
      var dispatchCount = 0;
      final adapter = _TypedToolAdapter(
        initialResponse: AgentResponse(
          text: '',
          toolCalls: <ToolCall>[
            ToolCall(
              id: 'call-1',
              toolId: 'battery_info',
              rawArguments: rawArgs,
              hasRawArguments: true,
            ),
          ],
          toolCallSource: ToolCallSource.flutterGemmaTyped,
        ),
        continuationResponse: const AgentResponse(
          text:
              'I could not use the battery tool because its arguments were malformed.',
        ),
      );
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: adapter,
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async {
              dispatchCount += 1;
              return const ToolResult.success('battery ok');
            },
          ),
        ]),
        notifier: _RecordingNotifier(),
      );

      final result = await loop.run(
        'can you check my battery?',
        sessionKey: 'agent:main',
      );

      expect(result.sessionResult, SessionResult.completed);
      expect(
        result.text,
        'I could not use the battery tool because its arguments were malformed.',
      );
      expect(dispatchCount, 0);
      expect(adapter.appendedToolNames, const <String>['battery_info']);
      expect(adapter.continuationCalls, 1);
      expect(
        result.toolResults.single.metadata['reason'],
        'malformed_tool_call',
      );
    }
  });

  test('empty-schema typed tool rejects wrappers and unknown keys', () async {
    final badArgs = <Map<String, Object?>>[
      <String, Object?>{'parameters': <String, Object?>{}},
      <String, Object?>{
        'parameters': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
        },
      },
      <String, Object?>{'unknown': true},
    ];

    for (final args in badArgs) {
      var dispatchCount = 0;
      final adapter = _TypedToolAdapter(
        initialResponse: AgentResponse(
          text: '',
          toolCalls: <ToolCall>[
            ToolCall(
              id: 'call-1',
              toolId: 'battery_info',
              arguments: args,
              rawArguments: args,
              hasRawArguments: true,
            ),
          ],
          toolCallSource: ToolCallSource.flutterGemmaTyped,
        ),
        continuationResponse: const AgentResponse(
          text: 'I tried the battery tool, but its arguments were not valid.',
        ),
      );
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: adapter,
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'battery_info',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async {
              dispatchCount += 1;
              return const ToolResult.success('battery ok');
            },
          ),
        ]),
        notifier: _RecordingNotifier(),
      );

      final result = await loop.run(
        'can you check my battery?',
        sessionKey: 'agent:main',
      );

      expect(result.sessionResult, SessionResult.completed);
      expect(
        result.text,
        'I tried the battery tool, but its arguments were not valid.',
      );
      expect(dispatchCount, 0);
      expect(adapter.appendedToolNames, const <String>['battery_info']);
      expect(adapter.continuationCalls, 1);
      expect(
        result.toolResults.single.metadata['reason'],
        anyOf('malformed_tool_call', 'schema_passed_as_args'),
      );
    }
  });

  test('tool failure is explained by continuation generation', () async {
    var dispatchCount = 0;
    final adapter = _TypedToolAdapter(
      initialResponse: const AgentResponse(
        text: '',
        toolCalls: <ToolCall>[
          ToolCall(
            id: 'call-1',
            toolId: 'battery_info',
            rawArguments: <String, Object?>{},
            hasRawArguments: true,
          ),
        ],
        toolCallSource: ToolCallSource.flutterGemmaTyped,
      ),
      continuationResponse: const AgentResponse(
        text:
            'I tried to read the battery info, but the tool returned no output.',
      ),
    );
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: adapter,
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: (call) async {
            dispatchCount += 1;
            return const ToolResult.success('');
          },
        ),
      ]),
      notifier: _RecordingNotifier(),
    );

    final result = await loop.run(
      'can you check my battery?',
      sessionKey: 'agent:main',
    );

    expect(result.sessionResult, SessionResult.completed);
    expect(
      result.text,
      'I tried to read the battery info, but the tool returned no output.',
    );
    expect(dispatchCount, 1);
    expect(adapter.continuationCalls, 1);
    expect(
      adapter.appendedResults.single.metadata['reason'],
      'typed_tool_call_without_output',
    );
  });

  test('post-tool completion missing fails only after continuation', () async {
    final adapter = _TypedToolAdapter(
      initialResponse: const AgentResponse(
        text: '',
        toolCalls: <ToolCall>[
          ToolCall(
            id: 'call-1',
            toolId: 'battery_info',
            rawArguments: <String, Object?>{},
            hasRawArguments: true,
          ),
        ],
        toolCallSource: ToolCallSource.flutterGemmaTyped,
      ),
      continuationResponse: const AgentResponse(text: ''),
    );
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: adapter,
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: (call) async => const ToolResult.success('battery ok'),
        ),
      ]),
      notifier: _RecordingNotifier(),
    );

    final result = await loop.run('check battery', sessionKey: 'agent:main');

    expect(result.sessionResult, SessionResult.failed);
    expect(result.reason, 'post_tool_completion_missing');
    expect(result.text, isEmpty);
    expect(adapter.appendedToolNames, const <String>['battery_info']);
    expect(adapter.continuationCalls, 1);
  });

  test('typed call takes precedence over JSON-looking text', () async {
    var dispatchCount = 0;
    final adapter = _TypedToolAdapter(
      initialResponse: const AgentResponse(
        text:
            '{"tool_call":{"id":"text-1","tool_id":"battery_info","arguments":{"type":"object","properties":{}}}}',
        toolCalls: <ToolCall>[
          ToolCall(
            id: 'typed-1',
            toolId: 'battery_info',
            rawArguments: <String, Object?>{},
            hasRawArguments: true,
          ),
        ],
        toolCallSource: ToolCallSource.flutterGemmaTyped,
      ),
      continuationResponse: const AgentResponse(text: 'Battery is available.'),
    );
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: adapter,
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: (call) async {
            dispatchCount += 1;
            return const ToolResult.success('battery ok');
          },
        ),
      ]),
      notifier: _RecordingNotifier(),
    );

    final result = await loop.run(
      'can you check my battery?',
      sessionKey: 'agent:main',
    );

    expect(result.sessionResult, SessionResult.completed);
    expect(dispatchCount, 1);
    expect(result.toolsUsed, const <String>['battery_info']);
    expect(adapter.appendedToolNames, const <String>['battery_info']);
    expect(adapter.continuationCalls, 1);
  });

  test('direct non-tool assistant turn persists normally', () async {
    final memoryFormation = _RecordingMemoryFormationService();
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      memoryFormationService: memoryFormation,
      modelAdapter: _QueueModelAdapter(<AgentResponse>[
        const AgentResponse(text: 'Hello from the reef.'),
      ]),
      toolCatalog: InMemoryToolCatalog(const <ToolDefinition>[]),
      notifier: _RecordingNotifier(),
    );

    final result = await loop.run('hello', sessionKey: 'agent:main');

    expect(result.sessionResult, SessionResult.completed);
    expect(result.text, 'Hello from the reef.');
    expect(result.toolsUsed, isEmpty);
    expect(memoryFormation.turns, hasLength(1));
    expect(
      memoryFormation.turns.single.assistantMessage,
      'Hello from the reef.',
    );
  });

  test('typed call source bypasses parser and avoids double dispatch', () async {
    var dispatchCount = 0;
    final adapter = _TypedToolAdapter(
      initialResponse: const AgentResponse(
        text:
            '<|tool_call>call:battery_info{"type":"object","properties":{}}<tool_call|>',
        toolCalls: <ToolCall>[
          ToolCall(
            id: 'typed-1',
            toolId: 'battery_info',
            rawArguments: <String, Object?>{},
            hasRawArguments: true,
          ),
        ],
        toolCallSource: ToolCallSource.flutterGemmaTyped,
      ),
      continuationResponse: const AgentResponse(text: 'Battery is available.'),
    );
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: adapter,
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'battery_info',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: (call) async {
            dispatchCount += 1;
            return const ToolResult.success('battery ok');
          },
        ),
      ]),
      notifier: _RecordingNotifier(),
    );

    final result = await loop.run('check battery', sessionKey: 'agent:main');

    expect(result.sessionResult, SessionResult.completed);
    expect(dispatchCount, 1);
    expect(result.toolResults, hasLength(1));
    expect(adapter.appendedToolNames, const <String>['battery_info']);
  });

  test(
    'parallel typed calls append results in order and continue once',
    () async {
      final executed = <String>[];
      final adapter = _TypedToolAdapter(
        initialResponse: const AgentResponse(
          text: '',
          toolCalls: <ToolCall>[
            ToolCall(
              id: 'call-1',
              toolId: 'first',
              rawArguments: <String, Object?>{},
              hasRawArguments: true,
            ),
            ToolCall(
              id: 'call-2',
              toolId: 'second',
              rawArguments: <String, Object?>{},
              hasRawArguments: true,
            ),
          ],
          toolCallSource: ToolCallSource.flutterGemmaTyped,
        ),
        continuationResponse: const AgentResponse(text: 'done'),
      );
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: adapter,
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'first',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async {
              executed.add(call.toolId);
              return const ToolResult.success('first ok');
            },
          ),
          ToolDefinition(
            id: 'second',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async {
              executed.add(call.toolId);
              return const ToolResult.success('second ok');
            },
          ),
        ]),
        notifier: _RecordingNotifier(),
      );

      final result = await loop.run('run two tools', sessionKey: 'agent:main');

      expect(result.sessionResult, SessionResult.completed);
      expect(executed, const <String>['first', 'second']);
      expect(adapter.appendedToolNames, const <String>['first', 'second']);
      expect(adapter.continuationCalls, 1);
    },
  );

  test('generation failure returns failed result', () async {
    final notifier = _RecordingNotifier();
    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: _ThrowingModelAdapter(
        const LiteRtCrashShieldException('Low free RAM detected.'),
      ),
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'session_status',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
      ]),
      notifier: notifier,
    );

    final result = await loop.run(
      'protect the device',
      sessionKey: 'session-test',
    );

    expect(result.sessionResult, SessionResult.failed);
    expect(result.reason, 'generation_failure');
    expect(result.text, contains('Low free RAM detected.'));
    expect(notifier.freezeCalls, 0);
  });

  test(
    'compaction failure returns deterministic failed result instead of uncaught crash',
    () async {
      final notifier = _RecordingNotifier();
      final loop = _buildLoop(
        memoryIndex: memoryIndex,
        memoryFormer: memoryFormer,
        modelAdapter: _QueueModelAdapter(<AgentResponse>[
          const AgentResponse(
            text: '',
            toolCall: ToolCall(id: '1', toolId: 'recover'),
          ),
        ]),
        toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
          ToolDefinition(
            id: 'session_status',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'memory_search',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'notify',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
          ToolDefinition(
            id: 'recover',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: _okExecute,
          ),
        ]),
        notifier: notifier,
        compactor: _ThrowingCompactor(),
      );

      final result = await loop.run(
        'compaction crash',
        sessionKey: 'agent:main',
        compactRequested: true,
      );

      expect(result.sessionResult, SessionResult.failed);
      expect(result.reason, 'compaction_failure');
      expect(result.text, contains('Compaction failed:'));
      expect(result.toolsUsed, isEmpty);
    },
  );

  test('runs compaction before dispatch in the tool loop', () async {
    final events = <String>[];
    final compactor = _RecordingCompactor(events);
    final notifier = _RecordingNotifier();

    final loop = _buildLoop(
      memoryIndex: memoryIndex,
      memoryFormer: memoryFormer,
      modelAdapter: _QueueModelAdapter(<AgentResponse>[
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: '1', toolId: 'recover'),
        ),
        const AgentResponse(text: 'done'),
      ]),
      toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
        ToolDefinition(
          id: 'session_status',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'memory_search',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'notify',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: _okExecute,
        ),
        ToolDefinition(
          id: 'recover',
          embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
          execute: (call) async {
            events.add('dispatch');
            return const ToolResult.success('ok');
          },
        ),
      ]),
      notifier: notifier,
      compactor: compactor,
    );

    await loop.run(
      'compact first',
      sessionKey: 'agent:main',
      compactRequested: true,
      conversationHistory: const <AgentMessage>[
        AgentMessage(
          role: AgentMessageRole.tool,
          content: 'old tool result',
          turnNumber: 1,
        ),
        AgentMessage(
          role: AgentMessageRole.assistant,
          content: 'recent history',
          turnNumber: 10,
        ),
      ],
      modelContextWindow: 1200,
      recentFiles: const <String>['lib/agent/agent_loop.dart'],
    );

    expect(events.first, anyOf('micro', 'auto', 'full'));
    expect(events.indexOf('dispatch'), greaterThan(events.indexOf('full')));
  });
}

AgentLoop _buildLoop({
  required MemoryIndex memoryIndex,
  required MemoryFormer memoryFormer,
  required AgentModelAdapter modelAdapter,
  required InMemoryToolCatalog toolCatalog,
  required _RecordingNotifier notifier,
  ReefCompactor? compactor,
  MemoryFormationService? memoryFormationService,
  Future<bool> Function(ToolCall call)? confirmToolCall,
}) {
  final assembler = ContextAssembler(
    memoryIndex: memoryIndex,
    embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
    toolCatalog: toolCatalog,
    skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
  );

  return AgentLoop(
    contextAssembler: assembler,
    compactor: compactor ?? _RecordingCompactor(<String>[]),
    modelAdapter: modelAdapter,
    toolRouter: ToolRouter(
      catalog: toolCatalog,
      mailbox: AgentMailbox(),
      confirmToolCall: confirmToolCall ?? (call) async => true,
    ),
    memoryFormer: memoryFormer,
    memoryFormationService: memoryFormationService,
    notifier: notifier,
  );
}

class _QueueModelAdapter implements AgentModelAdapter {
  _QueueModelAdapter(this._responses);

  final List<AgentResponse> _responses;
  var _index = 0;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    final response = _responses[_index];
    _index += 1;
    return response;
  }
}

class _StreamingQueueAdapter implements StreamingAgentModelAdapter {
  _StreamingQueueAdapter(this._responses);

  final List<String> _responses;
  var _index = 0;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    return const AgentResponseParser().parse(_responses[_index++]);
  }

  @override
  Stream<String> generateTextStream(
    AssembleResult context, {
    required int maxTokens,
  }) async* {
    yield _responses[_index++];
  }
}

class _TypedToolAdapter implements ToolResponseModelAdapter {
  _TypedToolAdapter({
    required this.initialResponse,
    required this.continuationResponse,
  });

  final AgentResponse initialResponse;
  final AgentResponse continuationResponse;
  final List<String> appendedToolNames = <String>[];
  final List<ToolResult> appendedResults = <ToolResult>[];
  var continuationCalls = 0;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    return initialResponse;
  }

  @override
  Future<void> appendToolResponse({
    required ToolCall toolCall,
    required ToolResult result,
  }) async {
    appendedToolNames.add(toolCall.toolId);
    appendedResults.add(result);
  }

  @override
  Future<AgentResponse> continueAfterToolResponses({
    required int maxTokens,
  }) async {
    continuationCalls += 1;
    return continuationResponse;
  }
}

class _RecordingTranscriptSink implements RuntimeTranscriptSink {
  final List<RuntimeTranscriptEvent> events = <RuntimeTranscriptEvent>[];

  @override
  Future<void> applyRuntimeTranscriptEvent(RuntimeTranscriptEvent event) async {
    events.add(event);
  }
}

class _RecordingMemoryFormationService implements MemoryFormationService {
  final List<CompletedTurnSnapshot> turns = <CompletedTurnSnapshot>[];

  @override
  Future<MemoryFormationResult> extract(CompletedTurnSnapshot turn) async {
    turns.add(turn);
    return const MemoryFormationResult(facts: [], isAmbiguous: false);
  }
}

class _FixedEmbedder implements IntentEmbedder {
  const _FixedEmbedder(this._embedding);

  final List<double> _embedding;

  @override
  Future<List<double>> embed(String text) async => _embedding;
}

class _FixedSemanticEmbedder implements SemanticTextEmbedder {
  const _FixedSemanticEmbedder(this._embedding);

  final List<double> _embedding;

  @override
  String get modelId => 'test-embedder';

  @override
  Future<List<double>> embedDocument(String text) async => _embedding;

  @override
  Future<List<double>> embedQuery(String text) async => _embedding;
}

class _ThrowingModelAdapter implements AgentModelAdapter {
  _ThrowingModelAdapter(this._error);

  final Object _error;

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) async {
    throw _error;
  }
}

class _InlineSummarizer implements CompactionSummarizer {
  const _InlineSummarizer(this._events);

  final List<String> _events;

  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    _events.add('summarize');
    return 'summary';
  }
}

class _RecordingCompactor extends ReefCompactor {
  _RecordingCompactor(this._events)
    : super(summarizer: _InlineSummarizer(_events));

  final List<String> _events;

  @override
  AssembleResult microCompact(AssembleResult context) {
    _events.add('micro');
    return super.microCompact(context);
  }

  @override
  Future<AssembleResult> autoCompact(
    AssembleResult context, {
    required int reserveTokens,
    required int maxSummaryTokens,
  }) async {
    _events.add('auto');
    return super.autoCompact(
      context,
      reserveTokens: reserveTokens,
      maxSummaryTokens: maxSummaryTokens,
    );
  }

  @override
  Future<AssembleResult> fullCompact(
    AssembleResult context, {
    bool reInjectRecentFiles = false,
    bool reInjectActiveSkills = false,
  }) async {
    _events.add('full');
    return super.fullCompact(
      context,
      reInjectRecentFiles: reInjectRecentFiles,
      reInjectActiveSkills: reInjectActiveSkills,
    );
  }
}

class _ThrowingCompactor extends ReefCompactor {
  _ThrowingCompactor() : super(summarizer: const _InlineSummarizer(<String>[]));

  @override
  AssembleResult microCompact(AssembleResult context) {
    throw StateError('compact boom');
  }

  @override
  Future<AssembleResult> fullCompact(
    AssembleResult context, {
    bool reInjectRecentFiles = false,
    bool reInjectActiveSkills = false,
  }) async {
    throw StateError('compact boom');
  }
}

class _RecordingNotifier implements AgentNotifier {
  var freezeCalls = 0;

  @override
  Future<void> freezeSession({
    required String sessionKey,
    required String reason,
    required String title,
    required String body,
  }) async {
    freezeCalls += 1;
  }
}

Future<ToolResult> _okExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}

Future<ToolResult> _failingExecute(ToolCall call) async {
  throw StateError('boom');
}
