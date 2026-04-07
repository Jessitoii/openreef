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
import 'package:openreef/ui/agent_loop_chat_session.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'controller exposes pending approval and resolves it through approve',
    () async {
      final controller = MainAgentApprovalController();

      final approvalFuture = controller.confirmToolCall(
        const ToolCall(
          id: 'call-1',
          toolId: 'volume_set',
          arguments: <String, Object?>{'level': 0.25},
        ),
      );

      expect(controller.pendingApproval?.toolId, 'volume_set');
      expect(controller.pendingApproval?.arguments['level'], 0.25);

      controller.approvePendingApproval();
      await expectLater(approvalFuture, completion(isTrue));
      expect(controller.pendingApproval, isNull);
    },
  );

  test('controller can reject a pending approval', () async {
    final controller = MainAgentApprovalController();

    final approvalFuture = controller.confirmToolCall(
      const ToolCall(id: 'call-2', toolId: 'volume_set'),
    );

    controller.rejectPendingApproval();

    await expectLater(approvalFuture, completion(isFalse));
    expect(controller.pendingApproval, isNull);
  });

  test(
    'controller surfaces mailbox approval and clears it after approve',
    () async {
      final mailbox = AgentMailbox(idGenerator: () => 'mailbox-1');
      addTearDown(mailbox.dispose);
      final controller = MainAgentApprovalController(mailbox: mailbox);

      final decisionFuture = mailbox.requestApproval(
        workerSessionKey: 'agent:main:sub:worker-1',
        call: const ToolCall(
          id: 'call-mailbox',
          toolId: 'volume_set',
          arguments: <String, Object?>{'level': 0.3},
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingApproval?.toolId, 'volume_set');

      controller.approvePendingApproval();

      final decision = await decisionFuture;
      expect(decision.isApproved, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.pendingApproval, isNull);
    },
  );

  test('controller clears mailbox approval after timeout resolution', () async {
    final mailbox = AgentMailbox(
      idGenerator: () => 'mailbox-timeout',
      config: const MailboxDispatchConfig(
        approvalTimeout: Duration(milliseconds: 10),
      ),
    );
    addTearDown(mailbox.dispose);
    final controller = MainAgentApprovalController(mailbox: mailbox);

    await mailbox.requestApproval(
      workerSessionKey: 'agent:main:sub:worker-timeout',
      call: const ToolCall(id: 'call-timeout', toolId: 'volume_set'),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.pendingApproval, isNull);
  });

  test(
    'chat session maps completed / frozen / failed results distinctly',
    () async {
      final completedSession = await _runSessionWithResult(
        const AgentLoopResult(
          sessionResult: SessionResult.completed,
          text: 'done',
          reason: 'completed',
        ),
      );
      expect(
        completedSession.messages.last.sender,
        ChatMessageSender.assistant,
      );
      expect(completedSession.messages.last.text, 'done');
      expect(
        completedSession.activities.single.status,
        SubAgentActivityStatus.completed,
      );

      final frozenSession = await _runSessionWithResult(
        const AgentLoopResult(
          sessionResult: SessionResult.frozen,
          text: '',
          reason: 'rejection_loop',
        ),
      );
      expect(frozenSession.messages.last.sender, ChatMessageSender.assistant);
      expect(
        frozenSession.messages.last.text,
        contains('same blocked tool request'),
      );
      expect(
        frozenSession.activities.single.status,
        SubAgentActivityStatus.failed,
      );

      final failedSession = await _runSessionWithResult(
        const AgentLoopResult(
          sessionResult: SessionResult.failed,
          text: '',
          reason: 'generation_failure',
        ),
      );
      expect(failedSession.messages.last.sender, ChatMessageSender.assistant);
      expect(
        failedSession.messages.last.text,
        'The agent turn failed during model generation.',
      );
      expect(
        failedSession.activities.single.status,
        SubAgentActivityStatus.failed,
      );
    },
  );
}

Future<AgentLoopChatSession> _runSessionWithResult(
  AgentLoopResult result,
) async {
  final storage = MemoryStorage(
    SqliteMemoryStorageBackend(
      path: inMemoryDatabasePath,
      databaseFactory: databaseFactoryFfi,
    ),
  );
  await storage.initialize();
  final memoryIndex = MemoryIndex(storage);
    final memoryFormer = MemoryFormer(
      storage: storage,
      memoryIndex: memoryIndex,
      embedder: const _FixedSemanticEmbedder(<double>[1, 0, 0]),
    );
  final assembler = ContextAssembler(
    memoryIndex: memoryIndex,
    embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
    toolCatalog: InMemoryToolCatalog(<ToolDefinition>[
      ToolDefinition(
        id: 'session_status',
        embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
        execute: (call) async => const ToolResult.success('ok'),
      ),
    ]),
    skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
  );
  final session = AgentLoopChatSession(
    agentLoop: _StubAgentLoop(
      result: result,
      contextAssembler: assembler,
      memoryFormer: memoryFormer,
    ),
  );
  addTearDown(storage.close);
  await session.sendMessage('hello');
  return session;
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

class _StubAgentLoop extends AgentLoop {
  _StubAgentLoop({
    required this.result,
    required super.contextAssembler,
    required super.memoryFormer,
  }) : super(
         compactor: const ReefCompactor(summarizer: _StaticSummarizer()),
         modelAdapter: const _UnusedModelAdapter(),
         toolRouter: ToolRouter(
           catalog: InMemoryToolCatalog(<ToolDefinition>[
             ToolDefinition(
               id: 'session_status',
               embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
               execute: _okExecute,
             ),
           ]),
           mailbox: AgentMailbox(),
           confirmToolCall: (call) async => true,
         ),
         notifier: const NoopAgentNotifier(),
       );

  final AgentLoopResult result;

  @override
  Future<AgentLoopResult> run(
    String userMessage, {
    required String sessionKey,
    List<AgentMessage> conversationHistory = const <AgentMessage>[],
    int modelContextWindow = 8192,
    bool compactRequested = false,
    List<String> recentFiles = const <String>[],
  }) async {
    return result;
  }
}

class _UnusedModelAdapter implements AgentModelAdapter {
  const _UnusedModelAdapter();

  @override
  Future<AgentResponse> generate(
    AssembleResult context, {
    required int maxTokens,
  }) {
    throw UnimplementedError('unused in stub loop');
  }
}

class _StaticSummarizer implements CompactionSummarizer {
  const _StaticSummarizer();

  @override
  Future<String> summarize(
    List<AgentMessage> messages, {
    required int maxTokens,
  }) async => 'summary';
}

Future<ToolResult> _okExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}
