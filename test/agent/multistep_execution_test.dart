import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_notifier.dart';
import 'package:openreef/agent/agent_task_executor.dart';
import 'package:openreef/agent/execution_log.dart';
import 'package:openreef/agent/execution_request.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('executor preserves multi-step tool chaining and logs one execution', () async {
    final storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    addTearDown(storage.close);

    final memoryIndex = MemoryIndex(storage);
    final memoryFormer = MemoryFormer(
      storage: storage,
      memoryIndex: memoryIndex,
      embedder: const _FixedSemanticEmbedder(),
    );
    final logStore = InMemoryExecutionLogStore();

    final loop = AgentLoop(
      contextAssembler: ContextAssembler(
        memoryIndex: memoryIndex,
        embedder: const _FixedIntentEmbedder(),
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
            id: 'battery_info',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async => const ToolResult.success('battery 42%'),
          ),
          ToolDefinition(
            id: 'volume_set',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            argumentSchema: const <ToolArgumentSpec>[
              ToolArgumentSpec(
                name: 'level',
                type: ToolArgumentType.doubleValue,
              ),
            ],
            execute: (call) async => const ToolResult.success('volume max'),
          ),
        ]),
        skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
      ),
      compactor: ReefCompactor(summarizer: const _NoopSummarizer()),
      modelAdapter: _QueueModelAdapter(<AgentResponse>[
        const AgentResponse(
          text: '',
          toolCall: ToolCall(id: 'call-1', toolId: 'battery_info'),
        ),
        const AgentResponse(
          text: '',
          toolCall: ToolCall(
            id: 'call-2',
            toolId: 'volume_set',
            arguments: <String, Object?>{'level': 1.0},
          ),
        ),
        const AgentResponse(text: 'Battery checked and volume set to max.'),
      ]),
      toolRouter: ToolRouter(
        catalog: InMemoryToolCatalog(<ToolDefinition>[
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
            id: 'battery_info',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            execute: (call) async => const ToolResult.success('battery 42%'),
          ),
          ToolDefinition(
            id: 'volume_set',
            embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
            argumentSchema: const <ToolArgumentSpec>[
              ToolArgumentSpec(
                name: 'level',
                type: ToolArgumentType.doubleValue,
              ),
            ],
            execute: (call) async => const ToolResult.success('volume max'),
          ),
        ]),
        mailbox: AgentMailbox(),
        confirmToolCall: (call) async => true,
      ),
      memoryFormer: memoryFormer,
      notifier: const _NoopNotifier(),
    );

    final executor = AgentLoopTaskExecutor(
      agentLoop: loop,
      executionLogStore: logStore,
    );

    final result = await executor.execute(
      ExecutionRequest.fromUserMessage(
        sessionKey: 'agent:main',
        prompt: 'check battery then set volume to max',
        id: 'exec-1',
        createdAt: DateTime.utc(2026, 4, 7, 12),
      ),
    );

    expect(result.sessionResult, SessionResult.completed);
    expect(result.toolsUsed, const <String>['battery_info', 'volume_set']);
    expect(
      logStore.records.value,
      hasLength(1),
    );
    expect(logStore.records.value.single.id, 'exec-1');
    expect(
      logStore.records.value.single.toolsUsed,
      const <String>['battery_info', 'volume_set'],
    );
    expect(logStore.records.value.single.status, ExecutionStatus.completed);
  });
}

class _QueueModelAdapter implements AgentModelAdapter {
  _QueueModelAdapter(this._responses);

  final List<AgentResponse> _responses;
  int _index = 0;

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

class _FixedIntentEmbedder implements IntentEmbedder {
  const _FixedIntentEmbedder();

  @override
  Future<List<double>> embed(String text) async => const <double>[1, 0, 0, 0, 0, 0, 0];
}

class _FixedSemanticEmbedder implements SemanticTextEmbedder {
  const _FixedSemanticEmbedder();

  @override
  String get modelId => 'test-semantic';

  @override
  Future<List<double>> embedDocument(String text) async => const <double>[1, 0, 0];

  @override
  Future<List<double>> embedQuery(String text) async => const <double>[1, 0, 0];
}

class _NoopSummarizer implements CompactionSummarizer {
  const _NoopSummarizer();

  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async {
    return 'summary';
  }
}

class _NoopNotifier implements AgentNotifier {
  const _NoopNotifier();

  @override
  Future<void> freezeSession({
    required String sessionKey,
    required String reason,
    required String title,
    required String body,
  }) async {}
}

Future<ToolResult> _okExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}
