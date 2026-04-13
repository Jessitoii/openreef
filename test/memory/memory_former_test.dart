import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_fact.dart';
import 'package:openreef/memory/memory_former.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/memory_turn.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/models/hugging_face_token_store.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late MemoryIndex index;
  late MemoryFormer former;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    index = MemoryIndex(storage);
    final manager = await _ManagerHarness.create(
      runtime: _FakeEmbeddingRuntime(active: true, activeId: 'gecko-256'),
    );
    former = MemoryFormer(
      storage: storage,
      memoryIndex: index,
      embeddingModelManager: manager.manager,
    );
  });

  tearDown(() async {
    await storage.close();
  });

  test('writes durable memory and updates pointers for successful turns', () async {
    final occurredAt = DateTime.now().toUtc();
    await former.process(
      MemoryTurn(
        facts: const <MemoryFact>[
          MemoryFact(
            key: 'prefs_2026',
            fact: 'Prefers short responses.',
            category: 'user_prefs',
            importance: 4,
          ),
          MemoryFact(
            key: 'recent_topic',
            fact: 'Discussed memory architecture.',
            category: 'fact',
            importance: 2,
          ),
        ],
        hasFailedToolCalls: false,
        isAmbiguous: false,
        occurredAt: occurredAt,
      ),
    );

    final longTerm = await storage.readRecord(
      'prefs_2026',
      store: MemoryStoreKind.longTerm,
    );
    final shortTerm = await storage.readRecord(
      'recent_topic',
      store: MemoryStoreKind.shortTerm,
    );
    final pointerBlock = await index.toContextBlock();

    expect(longTerm?.content, 'Prefers short responses.');
    expect(shortTerm?.content, 'Discussed memory architecture.');
    expect(pointerBlock, contains('user_prefs       -> memory:prefs_2026'));
  });

  test('strict write discipline skips durable writes after failed tool calls', () async {
    final occurredAt = DateTime.now().toUtc();
    await former.process(
      MemoryTurn(
        facts: const <MemoryFact>[
          MemoryFact(
            key: 'prefs_failed',
            fact: 'Should never be stored long term.',
            category: 'user_prefs',
            importance: 5,
          ),
        ],
        hasFailedToolCalls: true,
        isAmbiguous: false,
        sessionKey: 'agent:main',
        occurredAt: occurredAt,
      ),
    );

    final durableRecord = await storage.readRecord(
      'prefs_failed',
      store: MemoryStoreKind.longTerm,
    );
    final guardRecord = await storage.readRecord(
      'agent:main_last_turn_status',
      store: MemoryStoreKind.shortTerm,
    );

    expect(durableRecord, isNull);
    expect(guardRecord?.content, 'error');
  });

  test('ambiguous turns are downgraded to short-term only', () async {
    final occurredAt = DateTime.now().toUtc();
    await former.process(
      MemoryTurn(
        facts: const <MemoryFact>[
          MemoryFact(
            key: 'work_projects',
            fact: 'Maybe the deadline moved to next week.',
            category: 'work_context',
            importance: 5,
          ),
        ],
        hasFailedToolCalls: false,
        isAmbiguous: true,
        occurredAt: occurredAt,
      ),
    );

    final longTerm = await storage.readRecord(
      'work_projects',
      store: MemoryStoreKind.longTerm,
    );
    final shortTerm = await storage.readRecord(
      'work_projects',
      store: MemoryStoreKind.shortTerm,
    );

    expect(longTerm, isNull);
    expect(shortTerm?.content, 'Maybe the deadline moved to next week.');
  });
}

class _ManagerHarness {
  const _ManagerHarness({required this.manager});

  final EmbeddingModelManager manager;

  static Future<_ManagerHarness> create({
    required _FakeEmbeddingRuntime runtime,
  }) async {
    final dir = await Directory.systemTemp.createTemp(
      'openreef_memory_former_test_',
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
    await manager.selectModel('gecko-256');
    await manager.installSelectedModel();
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
  _FakeEmbeddingRuntime({this.active = false, this.activeId = 'gecko-256'});

  bool active;
  String activeId;

  @override
  String? activeEmbedderId() => activeId;

  @override
  Future<EmbeddingModel> getActiveEmbedder() async => _FakeEmbeddingModel();

  @override
  bool hasActiveEmbedder() => active;

  @override
  Future<void> install({
    required ModelDescriptor descriptor,
    required String? hfToken,
    required void Function(double progress) onProgress,
  }) async {
    active = true;
    activeId = descriptor.storageFileName.substring(
      0,
      descriptor.storageFileName.lastIndexOf('.'),
    );
  }

  @override
  Future<bool> isInstalled(ModelDescriptor descriptor) async => active;
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
