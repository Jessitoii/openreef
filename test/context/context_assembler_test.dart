import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late MemoryIndex memoryIndex;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    memoryIndex = MemoryIndex(storage);

    final now = DateTime.utc(2026, 4, 4, 20);
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'prefs_2026',
        content: 'User prefers compact status updates.',
        category: 'user_prefs',
        importance: 5,
        createdAt: now,
      ),
    );
    await memoryIndex.rebuild();
  });

  tearDown(() async {
    await storage.close();
  });

  test('always injects the MemoryIndex context block', () async {
    final assembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
      toolCatalog: InMemoryToolCatalog(_toolFixtures),
      skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
    );

    final result = await assembler.assemble(
      sessionKey: 'agent:main',
      userMessage: 'what did you remember about me?',
      conversationHistory: const <AgentMessage>[],
      modelContextWindow: 4096,
    );

    expect(
      result.messages.any((message) => message.content.contains('[MEMORY INDEX]')),
      isTrue,
    );
  });

  test('tool selection includes required tools and caps the list at 8', () async {
    final assembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
      toolCatalog: InMemoryToolCatalog(_toolFixtures),
      skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
    );

    final selected = await assembler.selectTools(
      userMessage: 'remind me to call Ali tonight',
      intentSignal: const IntentSignal(
        primary: 'system',
        secondary: 'general',
        confidence: 0.9,
      ),
    );

    final ids = selected.map((tool) => tool.id).toList(growable: false);
    expect(ids, contains('session_status'));
    expect(ids, contains('memory_search'));
    expect(ids, contains('notify'));
    expect(selected.length, lessThanOrEqualTo(8));
  });

  test('skill gating injects at most 2 matching skills', () async {
    final assembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: const _FixedEmbedder(<double>[0, 0, 1, 0, 0, 0, 0]),
      toolCatalog: InMemoryToolCatalog(_toolFixtures),
      skillCatalog: InMemorySkillCatalog(
        const <SkillDefinition>[
          SkillDefinition(
            id: 'sleep_tracker',
            content: 'Track sleep',
            triggerPatterns: <String>['sleep'],
          ),
          SkillDefinition(
            id: 'medication_reminder',
            content: 'Track pills',
            triggerPatterns: <String>['pill'],
          ),
          SkillDefinition(
            id: 'wellness_journal',
            content: 'Track health',
            triggerPatterns: <String>['sleep', 'pill'],
          ),
        ],
      ),
    );

    final gated = assembler.gateSkills('sleep pill reminder');

    expect(gated.length, 2);
  });

  test('budget allocation uses 60/30/10 split and reserves 1024 output tokens', () async {
    final assembler = ContextAssembler(
      memoryIndex: memoryIndex,
      embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
      toolCatalog: InMemoryToolCatalog(_toolFixtures),
      skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
      memoryContextProvider: const _MemoryProvider(),
      standingOrderProvider: const _StandingOrderSource(),
    );

    final result = await assembler.assemble(
      sessionKey: 'agent:main',
      userMessage: 'find my meeting notes',
      conversationHistory: const <AgentMessage>[
        AgentMessage(
          role: AgentMessageRole.user,
          content: 'old message one',
          turnNumber: 1,
        ),
        AgentMessage(
          role: AgentMessageRole.assistant,
          content: 'old message two',
          turnNumber: 2,
        ),
      ],
      modelContextWindow: 4096,
    );

    final budget = result.tokenBudget;
    final allocatable = budget.historyBudget + budget.memoryBudget + budget.standingOrderBudget;

    expect(budget.outputReserve, 1024);
    expect(budget.historyBudget, (allocatable * 0.6).floor());
    expect(budget.memoryBudget, (allocatable * 0.3).floor());
    expect(
      budget.standingOrderBudget,
      allocatable - budget.historyBudget - budget.memoryBudget,
    );
  });
}

class _FixedEmbedder implements IntentEmbedder {
  const _FixedEmbedder(this._embedding);

  final List<double> _embedding;

  @override
  Future<List<double>> embed(String text) async => _embedding;
}

class _MemoryProvider implements MemoryContextProvider {
  const _MemoryProvider();

  @override
  Future<List<AgentMessage>> retrieveRelevantMemories({
    required String userMessage,
    required IntentSignal intentSignal,
    required int maxTokens,
  }) async {
    return const <AgentMessage>[
      AgentMessage(
        role: AgentMessageRole.memory,
        content: 'Memory fact for retrieval',
        turnNumber: 0,
      ),
    ];
  }
}

class _StandingOrderSource implements StandingOrderProvider {
  const _StandingOrderSource();

  @override
  Future<List<AgentMessage>> loadStandingOrders({
    required String sessionKey,
    required int maxTokens,
  }) async {
    return const <AgentMessage>[
      AgentMessage(
        role: AgentMessageRole.standingOrder,
        content: 'Always provide concise updates.',
        turnNumber: 0,
      ),
    ];
  }
}

final List<ToolDefinition> _toolFixtures = <ToolDefinition>[
  ToolDefinition(
    id: 'session_status',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'memory_search',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'notify',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'phone_call',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    requiresConfirmation: true,
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'calendar_read',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'calendar_write',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'user_confirm',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'web_search',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'llm_task',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
  ToolDefinition(
    id: 'extra_tool',
    embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
    execute: _noopExecute,
  ),
];

Future<ToolResult> _noopExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}
