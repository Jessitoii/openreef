import 'dart:math' as math;

import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_match.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/models/embedding_model_manager.dart';

enum SemanticMemoryRetrievalStatus {
  success,
  noMatches,
  unavailable,
  degraded,
}

class SemanticMemoryRetrievalResult {
  const SemanticMemoryRetrievalResult({
    required this.status,
    required this.modelIdUsed,
    required this.matches,
    this.message = '',
    this.skippedCrossModelCount = 0,
    this.embeddingModelReady = false,
  });

  final SemanticMemoryRetrievalStatus status;
  final String modelIdUsed;
  final List<SemanticMemoryMatch> matches;
  final String message;
  final int skippedCrossModelCount;
  final bool embeddingModelReady;

  bool get isSuccess => status == SemanticMemoryRetrievalStatus.success;

  bool get hasMatches => matches.isNotEmpty;

  bool get isDegraded =>
      status == SemanticMemoryRetrievalStatus.unavailable ||
      status == SemanticMemoryRetrievalStatus.degraded;

  SemanticMemoryRetrievalResult copyWith({
    SemanticMemoryRetrievalStatus? status,
    String? modelIdUsed,
    List<SemanticMemoryMatch>? matches,
    String? message,
    int? skippedCrossModelCount,
    bool? embeddingModelReady,
  }) {
    return SemanticMemoryRetrievalResult(
      status: status ?? this.status,
      modelIdUsed: modelIdUsed ?? this.modelIdUsed,
      matches: matches ?? this.matches,
      message: message ?? this.message,
      skippedCrossModelCount:
          skippedCrossModelCount ?? this.skippedCrossModelCount,
      embeddingModelReady: embeddingModelReady ?? this.embeddingModelReady,
    );
  }
}

class SemanticMemoryRetriever {
  SemanticMemoryRetriever({
    required MemoryStorage storage,
    SemanticEmbeddingModelAccess? embeddingModelManager,
    SemanticTextEmbedder? embedder,
    this.defaultThreshold = 0.60,
  })  : assert(
          embeddingModelManager != null || embedder != null,
          'Provide a manager-backed embedder or an explicit legacy embedder.',
        ),
        _storage = storage,
        _embeddingModelManager =
            embeddingModelManager ??
            _StaticSemanticAccess(
              embedder: embedder!,
              modelId: embedder.modelId,
            );

  final MemoryStorage _storage;
  final SemanticEmbeddingModelAccess _embeddingModelManager;
  final double defaultThreshold;

  Future<SemanticMemoryRetrievalResult> search({
    required String query,
    int limit = 5,
    double? threshold,
    MemoryStoreKind? store,
    String? category,
  }) async {
    final normalizedQuery = _normalizeText(query);
    if (normalizedQuery.isEmpty) {
      return const SemanticMemoryRetrievalResult(
        status: SemanticMemoryRetrievalStatus.noMatches,
        modelIdUsed: 'none',
        matches: <SemanticMemoryMatch>[],
        message: 'empty_query',
      );
    }

    final readiness = await _embeddingModelManager.checkReadiness();
    if (!readiness.isReady) {
      return SemanticMemoryRetrievalResult(
        status: SemanticMemoryRetrievalStatus.unavailable,
        modelIdUsed: readiness.model?.id ?? 'none',
        matches: const <SemanticMemoryMatch>[],
        message: 'semantic_embedding_model_not_ready',
        embeddingModelReady: false,
      );
    }

    final embedder = await _embeddingModelManager.requireReadyEmbedder();
    final queryEmbedding = await embedder.embedQuery(normalizedQuery);
    final records = await _storage.readRecords(
      store: store,
      includeExpired: false,
    );
    final matches = <SemanticMemoryMatch>[];
    var skippedCrossModelCount = 0;
    for (final record in records) {
      if (category != null && category.isNotEmpty && record.category != category) {
        continue;
      }
      final embeddingRecord = await _storage.readEmbedding(record.key);
      if (embeddingRecord == null) {
        continue;
      }
      if (embeddingRecord.modelId != embedder.modelId) {
        skippedCrossModelCount += 1;
        continue;
      }
      if (embeddingRecord.embedding.length != queryEmbedding.length) {
        continue;
      }
      final similarity = _cosineSimilarity(queryEmbedding, embeddingRecord.embedding);
      if (similarity < (threshold ?? defaultThreshold)) {
        continue;
      }
      matches.add(
        SemanticMemoryMatch(
          record: record,
          score: similarity,
        ),
      );
    }
    matches.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final importanceCompare = right.record.importance.compareTo(
        left.record.importance,
      );
      if (importanceCompare != 0) {
        return importanceCompare;
      }
      return right.record.createdAt.compareTo(left.record.createdAt);
    });
    final limited = matches.length <= limit
        ? matches
        : matches.take(limit).toList(growable: false);
    if (limited.isEmpty) {
      return SemanticMemoryRetrievalResult(
        status: skippedCrossModelCount > 0
            ? SemanticMemoryRetrievalStatus.degraded
            : SemanticMemoryRetrievalStatus.noMatches,
        modelIdUsed: embedder.modelId,
        matches: const <SemanticMemoryMatch>[],
        message: skippedCrossModelCount > 0
          ? 'cross_model_matches_excluded'
          : 'no_semantic_memory_matches',
        skippedCrossModelCount: skippedCrossModelCount,
        embeddingModelReady: true,
      );
    }
    return SemanticMemoryRetrievalResult(
      status: skippedCrossModelCount > 0
          ? SemanticMemoryRetrievalStatus.degraded
          : SemanticMemoryRetrievalStatus.success,
      modelIdUsed: embedder.modelId,
      matches: List<SemanticMemoryMatch>.unmodifiable(limited),
      message: skippedCrossModelCount > 0
          ? 'cross_model_matches_excluded'
          : 'memory_retrieval_success',
      skippedCrossModelCount: skippedCrossModelCount,
      embeddingModelReady: true,
    );
  }

  String normalizeContent(String value) => _normalizeText(value);

  double _cosineSimilarity(List<double> left, List<double> right) {
    var dot = 0.0;
    var leftMagnitude = 0.0;
    var rightMagnitude = 0.0;
    for (var index = 0; index < left.length; index++) {
      dot += left[index] * right[index];
      leftMagnitude += left[index] * left[index];
      rightMagnitude += right[index] * right[index];
    }
    if (leftMagnitude == 0 || rightMagnitude == 0) {
      return 0;
    }
    return dot / (math.sqrt(leftMagnitude) * math.sqrt(rightMagnitude));
  }

  String _normalizeText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
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

class SemanticMemoryContextProvider implements MemoryContextProvider {
  const SemanticMemoryContextProvider(this._retriever);

  static const int _maxRecords = 6;

  final SemanticMemoryRetriever _retriever;

  @override
  Future<List<AgentMessage>> retrieveRelevantMemories({
    required String userMessage,
    required IntentSignal intentSignal,
    required int maxTokens,
  }) async {
    if (maxTokens <= 0) {
      return const <AgentMessage>[];
    }

    final result = await _retriever.search(
      query: userMessage,
      limit: _maxRecords,
    );
    if (result.status == SemanticMemoryRetrievalStatus.unavailable) {
      return <AgentMessage>[
        AgentMessage(
          role: AgentMessageRole.memory,
          content: '[MEMORY RETRIEVAL DEFERRED]\n'
              'status: unavailable\n'
              'reason: ${result.message}\n'
              'modelId: ${result.modelIdUsed}\n'
              '[END MEMORY RETRIEVAL DEFERRED]',
          turnNumber: 0,
          metadata: <String, Object?>{
            'memory_retrieval_status': result.status.name,
            'memory_retrieval_reason': result.message,
            'embedding_model_id_used': result.modelIdUsed,
            'memory_retrieval_skipped_no_embedder': true,
            'memory_retrieval_degraded': true,
          },
        ),
      ];
    }

    final selected = <AgentMessage>[];
    var usedTokens = 0;
    for (final match in result.matches) {
      final message = AgentMessage(
        role: AgentMessageRole.memory,
        content: '[${match.record.category}] ${match.record.content}',
        turnNumber: 0,
        metadata: <String, Object?>{
          'memory_key': match.record.key,
          'category': match.record.category,
          'semantic_score': match.score,
          'embedding_model_id_used': result.modelIdUsed,
          'memory_retrieval_status': result.status.name,
        },
      );
      final estimatedTokens = message.content
          .trim()
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .length;
      if (usedTokens + estimatedTokens > maxTokens) {
        continue;
      }
      usedTokens += estimatedTokens;
      selected.add(message);
    }

    if (selected.isEmpty) {
      return const <AgentMessage>[];
    }

    if (result.skippedCrossModelCount > 0) {
      selected.insert(
        0,
        AgentMessage(
          role: AgentMessageRole.memory,
          content: '[MEMORY RETRIEVAL PARTIAL]\n'
              'status: degraded\n'
              'reason: ${result.message}\n'
              'modelId: ${result.modelIdUsed}\n'
              'excludedCrossModelMatches: ${result.skippedCrossModelCount}\n'
              '[END MEMORY RETRIEVAL PARTIAL]',
          turnNumber: 0,
          metadata: <String, Object?>{
            'memory_retrieval_status': result.status.name,
            'memory_retrieval_reason': result.message,
            'embedding_model_id_used': result.modelIdUsed,
            'memory_retrieval_degraded': true,
            'excluded_cross_model_matches': result.skippedCrossModelCount,
          },
        ),
      );
    }

    return selected;
  }
}
