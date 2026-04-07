import 'package:openreef/memory/memory_fact.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';

class MemoryDeduplicator {
  MemoryDeduplicator({
    required MemoryStorage storage,
    required SemanticMemoryRetriever retriever,
    this.nearDuplicateThreshold = 0.92,
  }) : _storage = storage,
       _retriever = retriever;

  final MemoryStorage _storage;
  final SemanticMemoryRetriever _retriever;
  final double nearDuplicateThreshold;

  Future<bool> isDuplicate(MemoryFact fact) async {
    final normalized = _retriever.normalizeContent(fact.fact);
    if (normalized.isEmpty) {
      return true;
    }

    final exact = await _storage.readRecordByNormalizedContent(
      normalized,
      store: MemoryStoreKind.longTerm,
    );
    if (exact != null) {
      return true;
    }

    final similar = await _retriever.search(
      query: fact.fact,
      limit: 1,
      threshold: nearDuplicateThreshold,
      store: MemoryStoreKind.longTerm,
      category: fact.category,
    );
    return similar.isNotEmpty;
  }
}
