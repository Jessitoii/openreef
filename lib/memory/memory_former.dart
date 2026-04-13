import 'package:openreef/memory/memory_deduplicator.dart';
import 'package:openreef/memory/memory_embedding_record.dart';
import 'package:openreef/memory/memory_fact.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/memory_turn.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';

/// Shapes new memory entries before they are persisted.
class MemoryFormer {
  MemoryFormer({
    required MemoryStorage storage,
    required MemoryIndex memoryIndex,
    SemanticEmbeddingModelAccess? embeddingModelManager,
    SemanticTextEmbedder? embedder,
    MemoryDeduplicator? deduplicator,
    SemanticMemoryRetriever? retriever,
  })  : assert(
          embeddingModelManager != null || embedder != null,
          'Provide a manager-backed embedder or an explicit legacy embedder.',
        ),
        _storage = storage,
        _memoryIndex = memoryIndex,
        _embeddingModelManager =
            embeddingModelManager ??
            _StaticSemanticAccess(
              embedder: embedder!,
              modelId: embedder.modelId,
            ),
        _retriever =
            retriever ??
            SemanticMemoryRetriever(
              storage: storage,
              embeddingModelManager: embeddingModelManager ??
                  _StaticSemanticAccess(
                    embedder: embedder!,
                    modelId: embedder.modelId,
                  ),
            ),
        _deduplicator =
            deduplicator ??
            MemoryDeduplicator(
              storage: storage,
              retriever:
                  retriever ??
                  SemanticMemoryRetriever(
                    storage: storage,
                    embeddingModelManager: embeddingModelManager ??
                        _StaticSemanticAccess(
                          embedder: embedder!,
                          modelId: embedder.modelId,
                        ),
                  ),
            );

  static const Duration _shortTermTtl = Duration(hours: 24);

  final MemoryStorage _storage;
  final MemoryIndex _memoryIndex;
  final SemanticEmbeddingModelAccess _embeddingModelManager;
  final SemanticMemoryRetriever _retriever;
  final MemoryDeduplicator _deduplicator;

  Future<void> process(MemoryTurn turn) async {
    if (turn.hasFailedToolCalls) {
      await _storage.saveRecord(
        MemoryRecord(
          store: MemoryStoreKind.shortTerm,
          key: _statusKey(turn),
          content: 'error',
          category: 'turn_status',
          importance: 1,
          createdAt: turn.occurredAt,
          expiresAt: turn.occurredAt.add(_shortTermTtl),
          metadata: <String, Object?>{
            if (turn.sessionKey != null) 'session_key': turn.sessionKey,
          },
        ),
      );
      return;
    }

    final facts = turn.isAmbiguous
        ? turn.facts.map((fact) => fact.copyWith(importance: 1)).toList()
        : turn.facts;

    for (final fact in facts) {
      await _persistFact(fact, occurredAt: turn.occurredAt);
    }
  }

  Future<void> _persistFact(
    MemoryFact fact, {
    required DateTime occurredAt,
  }) async {
    final store = fact.importance >= 3
        ? MemoryStoreKind.longTerm
        : MemoryStoreKind.shortTerm;
    final expiresAt =
        store == MemoryStoreKind.shortTerm ? occurredAt.add(_shortTermTtl) : null;
    final normalizedContent = _retriever.normalizeContent(fact.fact);
    if (normalizedContent.isEmpty) {
      return;
    }

    if (store == MemoryStoreKind.longTerm && await _deduplicator.isDuplicate(fact)) {
      return;
    }

    final embedder = await _embeddingModelManager.requireReadyEmbedder();
    final embedding = await embedder.embedDocument(fact.fact);

    await _storage.saveRecord(
      MemoryRecord(
        store: store,
        key: fact.key,
        content: fact.fact,
        category: fact.category,
        importance: fact.importance,
        createdAt: occurredAt,
        expiresAt: expiresAt,
        metadata: fact.metadata,
      ),
    );
    await _storage.saveEmbedding(
      MemoryEmbeddingRecord(
        memoryKey: fact.key,
        modelId: embedder.modelId,
        embedding: embedding,
        normalizedContent: normalizedContent,
        updatedAt: occurredAt,
      ),
    );

    if (store == MemoryStoreKind.longTerm && fact.category.isNotEmpty) {
      await _memoryIndex.updatePointer(
        category: fact.category,
        memoryKey: fact.key,
      );
    }
  }

  String _statusKey(MemoryTurn turn) {
    if (turn.sessionKey == null || turn.sessionKey!.isEmpty) {
      return 'last_turn_status';
    }

    return '${turn.sessionKey}_last_turn_status';
  }
}

class _StaticSemanticAccess implements SemanticEmbeddingModelAccess {
  _StaticSemanticAccess({required this.embedder, required this.modelId});

  final SemanticTextEmbedder embedder;
  final String modelId;

  @override
  String get selectedModelId => modelId;

  @override
  Future<EmbeddingModelReadiness> checkReadiness() async {
    return EmbeddingModelReadiness(
      status: EmbeddingModelReadinessStatus.ready,
      model: null,
      message: 'Legacy explicit embedder is ready.',
    );
  }

  @override
  Future<SemanticTextEmbedder> requireReadyEmbedder() async => embedder;
}
