import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/memory/memory_deduplicator.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_fact.dart';
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
  late MemoryDeduplicator deduplicator;

  setUp(() async {
    storage = MemoryStorage(
      SqliteMemoryStorageBackend(
        path: inMemoryDatabasePath,
        databaseFactory: databaseFactoryFfi,
      ),
    );
    await storage.initialize();
    final retriever = SemanticMemoryRetriever(
      storage: storage,
      embedder: _MappedSemanticEmbedder(<String, List<double>>{
        'prefers concise status updates.': const <double>[1, 0, 0],
        'likes short status updates.': const <double>[1, 0, 0],
        'prefers dark mode.': const <double>[0, 1, 0],
      }),
    );
    deduplicator = MemoryDeduplicator(
      storage: storage,
      retriever: retriever,
    );

    final now = DateTime.utc(2026, 4, 6, 12);
    await storage.saveRecord(
      MemoryRecord(
        store: MemoryStoreKind.longTerm,
        key: 'prefs_compact',
        content: 'Prefers concise status updates.',
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
        normalizedContent: 'prefers concise status updates.',
        updatedAt: now,
      ),
    );
  });

  tearDown(() async {
    await storage.close();
  });

  test('skips exact duplicates', () async {
    final duplicate = await deduplicator.isDuplicate(
      const MemoryFact(
        key: 'next',
        fact: 'Prefers concise status updates.',
        category: 'preference',
        importance: 5,
      ),
    );

    expect(duplicate, isTrue);
  });

  test('skips near duplicates in the same category', () async {
    final duplicate = await deduplicator.isDuplicate(
      const MemoryFact(
        key: 'next',
        fact: 'Likes short status updates.',
        category: 'preference',
        importance: 5,
      ),
    );

    expect(duplicate, isTrue);
  });

  test('allows distinct facts to be written', () async {
    final duplicate = await deduplicator.isDuplicate(
      const MemoryFact(
        key: 'next',
        fact: 'Prefers dark mode.',
        category: 'preference',
        importance: 5,
      ),
    );

    expect(duplicate, isFalse);
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
