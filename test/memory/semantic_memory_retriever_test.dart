import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
  });

  tearDown(() async {
    await storage.close();
  });

  test('retrieves semantic matches with ready managed embedder', () async {
    final retriever = SemanticMemoryRetriever(
      storage: storage,
      embeddingModelManager: _FixedSemanticAccess(
        modelId: 'gecko-256',
        readiness: const EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.ready,
        ),
        embedder: const _MappedSemanticEmbedder(<String, List<double>>{
          'short updates please': <double>[1, 0, 0],
          'user prefers concise status updates.': <double>[1, 0, 0],
        }),
      ),
    );
    final now = DateTime.utc(2026, 4, 6, 12);
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'prefs_compact',
        content: 'User prefers concise status updates.',
        category: 'preference',
        importance: 5,
        createdAt: now,
      ),
    );
    await storage.saveEmbedding(
      MemoryEmbeddingRecord(
        memoryKey: 'prefs_compact',
        modelId: 'gecko-256',
        embedding: const <double>[1, 0, 0],
        normalizedContent: 'user prefers concise status updates.',
        updatedAt: now,
      ),
    );

    final result = await retriever.search(query: 'short updates please');

    expect(result.status, SemanticMemoryRetrievalStatus.success);
    expect(result.modelIdUsed, 'gecko-256');
    expect(result.matches, isNotEmpty);
    expect(result.matches.first.record.key, 'prefs_compact');
  });

  test('returns explicit degraded result when embedder is not ready', () async {
    final retriever = SemanticMemoryRetriever(
      storage: storage,
      embeddingModelManager: _FixedSemanticAccess(
        modelId: 'none',
        readiness: const EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.downloadable,
        ),
        embedder: const _MappedSemanticEmbedder(<String, List<double>>{}),
      ),
    );

    final result = await retriever.search(query: 'short updates please');

    expect(result.status, SemanticMemoryRetrievalStatus.unavailable);
    expect(result.matches, isEmpty);
    expect(result.message, 'semantic_embedding_model_not_ready');
  });

  test('excludes cross-model embeddings without mixing comparison spaces', () async {
    final retriever = SemanticMemoryRetriever(
      storage: storage,
      embeddingModelManager: _FixedSemanticAccess(
        modelId: 'gecko-256',
        readiness: const EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.ready,
        ),
        embedder: const _MappedSemanticEmbedder(<String, List<double>>{
          'short updates please': <double>[1, 0, 0],
        }),
      ),
    );
    final now = DateTime.utc(2026, 4, 6, 12);
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'prefs_other',
        content: 'User prefers concise status updates.',
        category: 'preference',
        importance: 5,
        createdAt: now,
      ),
    );
    await storage.saveEmbedding(
      MemoryEmbeddingRecord(
        memoryKey: 'prefs_other',
        modelId: 'other-model',
        embedding: const <double>[1, 0, 0],
        normalizedContent: 'user prefers concise status updates.',
        updatedAt: now,
      ),
    );

    final result = await retriever.search(query: 'short updates please');

    expect(result.status, SemanticMemoryRetrievalStatus.degraded);
    expect(result.skippedCrossModelCount, 1);
    expect(result.matches, isEmpty);
  });
}

class _FixedSemanticAccess implements SemanticEmbeddingModelAccess {
  const _FixedSemanticAccess({
    required this.modelId,
    required this.readiness,
    required this.embedder,
  });

  final String modelId;
  final EmbeddingModelReadiness readiness;
  final SemanticTextEmbedder embedder;

  @override
  String get selectedModelId => modelId;

  @override
  Future<EmbeddingModelReadiness> checkReadiness() async => readiness;

  @override
  Future<SemanticTextEmbedder> requireReadyEmbedder() async => embedder;
}

class _MappedSemanticEmbedder implements SemanticTextEmbedder {
  const _MappedSemanticEmbedder(this._vectors);

  final Map<String, List<double>> _vectors;

  @override
  String get modelId => 'gecko-256';

  @override
  Future<List<double>> embedDocument(String text) async {
    return _vectors[text.toLowerCase()] ?? const <double>[0, 0, 1];
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    return _vectors[text.toLowerCase()] ?? const <double>[0, 0, 1];
  }
}
