import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage_backend.dart';
import 'package:openreef/memory/semantic_memory_match.dart';
import 'package:openreef/memory/memory_store_kind.dart';

class MemoryStorage {
  MemoryStorage(this._backend);

  final MemoryStorageBackend _backend;

  Future<void> initialize() => _backend.initialize();

  Future<void> saveRecord(MemoryRecord record) => _backend.saveRecord(record);

  Future<MemoryMutationResult> saveRecordSafely(
    MemoryRecord record, {
    MemoryRecord? previousRecord,
    MemoryEmbeddingRecord? preparedEmbedding,
    Future<void> Function()? rebuildIndex,
  }) {
    return _backend.saveRecordSafely(
      record,
      previousRecord: previousRecord,
      preparedEmbedding: preparedEmbedding,
      rebuildIndex: rebuildIndex,
    );
  }

  Future<MemoryRecord?> readRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _backend.fetchRecord(
      key,
      store: store,
      includeExpired: includeExpired,
    );
  }

  Future<List<MemoryRecord>> readRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _backend.fetchRecords(
      store: store,
      includeExpired: includeExpired,
    );
  }

  Future<void> saveEmbedding(MemoryEmbeddingRecord record) {
    return _backend.saveEmbedding(record);
  }

  Future<MemoryEmbeddingRecord?> readEmbedding(String key) {
    return _backend.fetchEmbedding(key);
  }

  Future<MemoryRecord?> readRecordByNormalizedContent(
    String normalizedContent, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _backend.fetchRecordByNormalizedContent(
      normalizedContent,
      store: store,
      includeExpired: includeExpired,
    );
  }

  Future<MemoryReadResult> readRecordsWithReport({
    MemoryStoreKind? store,
    bool includeExpired = false,
  }) {
    return _backend.fetchRecordsWithReport(
      store: store,
      includeExpired: includeExpired,
    );
  }

  Future<List<SemanticMemoryMatch>> searchByEmbedding({
    required List<double> queryEmbedding,
    int limit = 5,
    double threshold = 0,
    MemoryStoreKind? store,
    String? category,
    bool includeExpired = false,
  }) {
    return _backend.searchByEmbedding(
      queryEmbedding: queryEmbedding,
      limit: limit,
      threshold: threshold,
      store: store,
      category: category,
      includeExpired: includeExpired,
    );
  }

  Future<void> deleteRecord(String key) => _backend.deleteRecord(key);

  Future<MemoryMutationResult> deleteRecordSafely(
    MemoryRecord record, {
    Future<void> Function()? rebuildIndex,
  }) {
    return _backend.deleteRecordSafely(
      record,
      rebuildIndex: rebuildIndex,
    );
  }

  Future<void> deleteRecords({
    MemoryStoreKind? store,
    bool includeExpired = true,
    String? category,
  }) {
    return _backend.deleteRecords(
      store: store,
      includeExpired: includeExpired,
      category: category,
    );
  }

  Future<MemoryMutationResult> deleteRecordsSafely(
    List<MemoryRecord> records, {
    Future<void> Function()? rebuildIndex,
  }) {
    return _backend.deleteRecordsSafely(
      records,
      rebuildIndex: rebuildIndex,
    );
  }

  Future<void> savePointer(MemoryPointer pointer) => _backend.savePointer(pointer);

  Future<MemoryPointer?> readPointer(String category) {
    return _backend.fetchPointer(category);
  }

  Future<List<MemoryPointer>> readPointers() => _backend.fetchPointers();

  Future<void> deletePointer(String category) => _backend.deletePointer(category);

  Future<void> close() => _backend.close();
}
