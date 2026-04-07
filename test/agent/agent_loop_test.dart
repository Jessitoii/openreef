import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_loop.dart';
import 'package:openreef/agent/agent_model_adapter.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/agent_notifier.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/compactor.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/models/litert_bridge.dart';
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
    expect(notifier.freezeCalls, 0);
  });

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
