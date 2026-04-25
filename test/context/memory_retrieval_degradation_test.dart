import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/context/capability_retrieval.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/models/hugging_face_token_store.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'context assembly succeeds and marks memory unavailable when model is not ready',
    () async {
      final storage = MemoryStorage(
        SqliteMemoryStorageBackend(
          path: inMemoryDatabasePath,
          databaseFactory: databaseFactoryFfi,
        ),
      );
      await storage.initialize();
      final manager = await _ManagerHarness.create(
        runtime: _FakeEmbeddingRuntime(),
      );
      final assembler = ContextAssembler(
        memoryIndex: MemoryIndex(storage),
        embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
        toolCatalog: _EmptyToolCatalog(),
        skillCatalog: _EmptySkillCatalog(),
        memoryContextProvider: ManagedSemanticMemoryContextProvider(
          retriever: SemanticMemoryRetriever(
            storage: storage,
            embeddingModelManager: manager.manager,
          ),
          readinessProvider: manager.manager,
        ),
        capabilityIndex: CapabilityEmbeddingIndex(
          embedder: const _FixedSemanticTextEmbedder(),
        ),
        embeddingReadinessProvider: manager.manager,
      );

      final result = await assembler.assemble(
        sessionKey: 'session-1',
        userMessage: 'remember this please',
        conversationHistory: const <AgentMessage>[],
        modelContextWindow: 4096,
      );

      expect(result.compiledPackage, isNotNull);
      expect(result.compiledPackage!.memorySelection.degraded, isTrue);
      expect(
        result.compiledPackage!.prompt.toPrompt(),
        contains('[MEMORY RETRIEVAL UNAVAILABLE]'),
      );

      await storage.close();
    },
  );
}

class _ManagerHarness {
  const _ManagerHarness({required this.manager});

  final EmbeddingModelManager manager;

  static Future<_ManagerHarness> create({
    required _FakeEmbeddingRuntime runtime,
  }) async {
    final dir = await Directory.systemTemp.createTemp(
      'openreef_memory_ctx_test_',
    );
    final controller = SettingsController(
      store: SettingsStore(
        File('${dir.path}${Platform.pathSeparator}settings.json'),
      ),
    );
    await controller.initialize();
    final manager = EmbeddingModelManager(
      registry: const ModelRegistry(),
      settingsController: controller,
      tokenStore: _MemoryTokenStore(),
      runtime: runtime,
    );
    await manager.initialize();
    return _ManagerHarness(manager: manager);
  }
}

class _MemoryTokenStore implements HuggingFaceTokenStore {
  @override
  Future<void> deleteTokenForModel(String modelId) async {}

  @override
  Future<bool> hasTokenForModel(String modelId) async => false;

  @override
  Future<String?> readTokenForModel(String modelId) async => null;

  @override
  Future<void> writeTokenForModel(String modelId, String token) async {}
}

class _FakeEmbeddingRuntime implements EmbeddingModelRuntime {
  _FakeEmbeddingRuntime();

  @override
  String? activeEmbedderId() => null;

  @override
  Future<EmbeddingModel> getActiveEmbedder() async => _FakeEmbeddingModel();

  @override
  bool hasActiveEmbedder() => false;

  @override
  Future<void> install({
    required ModelDescriptor descriptor,
    required String? hfToken,
    required void Function(double progress) onProgress,
  }) async {}

  @override
  Future<void> activateInstalled(ModelDescriptor descriptor) async {}

  @override
  Future<bool> isInstalled(ModelDescriptor descriptor) async => false;
}

class _FakeEmbeddingModel implements EmbeddingModel {
  @override
  Future<void> close() async {}

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    return const <double>[1, 0, 0];
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    return List<List<double>>.filled(texts.length, const <double>[1, 0, 0]);
  }

  @override
  Future<int> getDimension() async => 3;
}

class _FixedEmbedder implements IntentEmbedder {
  const _FixedEmbedder(this._embedding);

  final List<double> _embedding;

  @override
  Future<List<double>> embed(String text) async => _embedding;
}

class _FixedSemanticTextEmbedder implements SemanticTextEmbedder {
  const _FixedSemanticTextEmbedder();

  @override
  String get modelId => 'test-embedder';

  @override
  Future<List<double>> embedDocument(String text) async => const <double>[
    1,
    0,
    0,
  ];

  @override
  Future<List<double>> embedQuery(String text) async => const <double>[1, 0, 0];
}

class _EmptyToolCatalog implements ToolCatalog {
  @override
  ToolDefinition? byId(String id) => null;

  @override
  List<ToolDefinition> listTools() => const <ToolDefinition>[];
}

class _EmptySkillCatalog implements SkillCatalog {
  @override
  List<SkillDefinition> listSkills() => const <SkillDefinition>[];

  @override
  void recordTurnState({
    required List<String> matchedSkillIds,
    required List<String> activeSkillIds,
  }) {}
}
