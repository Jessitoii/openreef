import 'package:openreef/memory/memory_pointer.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/semantic_memory_match.dart';
import 'package:openreef/memory/memory_store_kind.dart';

enum MemoryMutationStatus {
  successCommitted,
  failedNoWrite,
  failedRolledBack,
  failedInconsistentManualRepairNeeded,
}

enum MemoryMutationStage {
  validation,
  embeddingCompute,
  rowWrite,
  embeddingWrite,
  indexRebuild,
  rollback,
}

class MemoryMutationResult {
  const MemoryMutationResult({
    required this.status,
    required this.stage,
    required this.message,
    required this.store,
    this.affectedKey,
    this.rollbackSucceeded = true,
  });

  const MemoryMutationResult.success({
    required String message,
    required MemoryStoreKind store,
    String? affectedKey,
  }) : this(
          status: MemoryMutationStatus.successCommitted,
          stage: MemoryMutationStage.indexRebuild,
          message: message,
          store: store,
          affectedKey: affectedKey,
        );

  final MemoryMutationStatus status;
  final MemoryMutationStage stage;
  final String message;
  final MemoryStoreKind store;
  final String? affectedKey;
  final bool rollbackSucceeded;

  bool get isSuccess => status == MemoryMutationStatus.successCommitted;
}

class MemoryReadResult {
  const MemoryReadResult({
    required this.records,
    required this.skippedCount,
  });

  final List<MemoryRecord> records;
  final int skippedCount;
}

abstract class MemoryStorageBackend {
  Future<void> initialize();

  Future<void> saveRecord(MemoryRecord record);

  Future<MemoryMutationResult> saveRecordSafely(
    MemoryRecord record, {
    MemoryRecord? previousRecord,
    MemoryEmbeddingRecord? preparedEmbedding,
    Future<void> Function()? rebuildIndex,
  });

  Future<MemoryRecord?> fetchRecord(
    String key, {
    MemoryStoreKind? store,
    bool includeExpired = false,
  });

  Future<List<MemoryRecord>> fetchRecords({
    MemoryStoreKind? store,
    bool includeExpired = false,
  });

  Future<MemoryReadResult> fetchRecordsWithReport({
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

  Future<MemoryMutationResult> deleteRecordSafely(
    MemoryRecord record, {
    Future<void> Function()? rebuildIndex,
  });

  Future<void> deleteRecords({
    MemoryStoreKind? store,
    bool includeExpired = true,
    String? category,
  });

  Future<MemoryMutationResult> deleteRecordsSafely(
    List<MemoryRecord> records, {
    Future<void> Function()? rebuildIndex,
  });

  Future<void> savePointer(MemoryPointer pointer);

  Future<MemoryPointer?> fetchPointer(String category);

  Future<List<MemoryPointer>> fetchPointers();

  Future<void> deletePointer(String category);

  Future<void> close();
}
