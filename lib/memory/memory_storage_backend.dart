import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/semantic_memory_match.dart';
import 'package:openreef/memory/memory_store_kind.dart';

abstract class MemoryStorageBackend {
  Future<void> initialize();

  Future<void> saveRecord(MemoryRecord record);

  Future<MemoryRecord?> fetchRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  });

  Future<List<MemoryRecord>> fetchRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  });

  Future<void> saveEmbedding(MemoryEmbeddingRecord record);

  Future<MemoryEmbeddingRecord?> fetchEmbedding(String key);

  Future<MemoryRecord?> fetchRecordByNormalizedContent(
    String normalizedContent, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  });

  Future<List<SemanticMemoryMatch>> searchByEmbedding({
    required List<double> queryEmbedding,
    int limit = 5,
    double threshold = 0,
    MemoryStoreKind? store,
    String? category,
    bool includeExpired = false,
  });

  Future<void> deleteRecord(String key);

  Future<void> savePointer(MemoryPointer pointer);

  Future<MemoryPointer?> fetchPointer(String category);

  Future<List<MemoryPointer>> fetchPointers();

  Future<void> deletePointer(String category);

  Future<void> close();
}
