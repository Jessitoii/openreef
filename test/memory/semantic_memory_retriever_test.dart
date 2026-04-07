import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late MemoryStorage storage;
  late SemanticMemoryRetriever retriever;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    retriever = SemanticMemoryRetriever(
      storage: storage,
      embedder: _MappedSemanticEmbedder(<String, List<double>>{
        'short updates please': const <double>[1, 0, 0],
        'user prefers concise status updates.': const <double>[1, 0, 0],
        'status updates should be verbose and detailed.': const <double>[0, 1, 0],
      }),
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
        modelId: 'test-embedder',
        embedding: const <double>[1, 0, 0],
        normalizedContent: 'user prefers concise status updates.',
        updatedAt: now,
      ),
    );

    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'prefs_verbose',
        content: 'Status updates should be verbose and detailed.',
        category: 'preference',
        importance: 5,
        createdAt: now,
      ),
    );
    await storage.saveEmbedding(
      MemoryEmbeddingRecord(
        memoryKey: 'prefs_verbose',
        modelId: 'test-embedder',
        embedding: const <double>[0, 1, 0],
        normalizedContent: 'status updates should be verbose and detailed.',
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await storage.close();
  });

  test('retrieves semantic matches without relying on keyword overlap', () async {
    final matches = await retriever.search(
      query: 'short updates please',
      limit: 2,
      threshold: 0.5,
    );

    expect(matches, isNotEmpty);
    expect(matches.first.record.key, 'prefs_compact');
    expect(matches.first.score, greaterThan(0.99));
  });
}

class _MappedSemanticEmbedder implements SemanticTextEmbedder {
  const _MappedSemanticEmbedder(this._vectors);

  final Map<String, List<double>> _vectors;

  @override
  String get modelId => 'test-embedder';

  @override
  Future<List<double>> embedDocument(String text) async {
    return _vectors[text.toLowerCase()] ?? const <double>[0, 0, 1];
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    return _vectors[text.toLowerCase()] ?? const <double>[0, 0, 1];
  }
}
