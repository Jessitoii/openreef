import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/memory/semantic_memory_match.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';

class SemanticMemoryRetriever {
  SemanticMemoryRetriever({
    required MemoryStorage storage,
    required SemanticTextEmbedder embedder,
    this.defaultThreshold = 0.60,
  }) : _storage = storage,
       _embedder = embedder;

  final MemoryStorage _storage;
  final SemanticTextEmbedder _embedder;
  final double defaultThreshold;

  Future<List<SemanticMemoryMatch>> search({
    required String query,
    int limit = 5,
    double? threshold,
    MemoryStoreKind? store,
    String? category,
  }) async {
    final normalizedQuery = _normalizeText(query);
    if (normalizedQuery.isEmpty) {
      return const <SemanticMemoryMatch>[];
    }

    try {
      final embedding = await _embedder.embedQuery(normalizedQuery);
      return _storage.searchByEmbedding(
        queryEmbedding: embedding,
        limit: limit,
        threshold: threshold ?? defaultThreshold,
        store: store,
        category: category,
      );
    } on Exception {
      return const <SemanticMemoryMatch>[];
    } on Error {
      return const <SemanticMemoryMatch>[];
    }
  }

  String normalizeContent(String value) => _normalizeText(value);

  String get modelId => _embedder.modelId;

  String _normalizeText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }
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

    final matches = await _retriever.search(
      query: userMessage,
      limit: _maxRecords,
    );

    final selected = <AgentMessage>[];
    var usedTokens = 0;
    for (final match in matches) {
      final message = AgentMessage(
        role: AgentMessageRole.memory,
        content: '[${match.record.category}] ${match.record.content}',
        turnNumber: 0,
        metadata: <String, Object?>{
          'memory_key': match.record.key,
          'category': match.record.category,
          'semantic_score': match.score,
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

    return selected;
  }
}
