import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/semantic_memory_retriever.dart';

class ContextRetriever {
  const ContextRetriever({
    required MemoryIndex memoryIndex,
    required MemoryContextProvider memoryContextProvider,
    required StandingOrderProvider standingOrderProvider,
  }) : _memoryIndex = memoryIndex,
       _memoryContextProvider = memoryContextProvider,
       _standingOrderProvider = standingOrderProvider;

  final MemoryIndex _memoryIndex;
  final MemoryContextProvider _memoryContextProvider;
  final StandingOrderProvider _standingOrderProvider;

  Future<RetrievedContextSources> retrieve({
    required String sessionKey,
    required String userMessage,
    required ContextPlan plan,
    required IntentSignal intentSignal,
  }) async {
    final memoryIndexBlock = await _memoryIndex.toContextBlock();
    final memoryMessages = await _memoryContextProvider
        .retrieveRelevantMemories(
          userMessage: userMessage,
          intentSignal: intentSignal,
          maxTokens: plan.memoryRetrievalPlan.totalBudget,
        );
    final memoryStatus = memoryMessages.isEmpty
        ? SemanticMemoryRetrievalStatus.noMatches
        : memoryMessages.any(
            (message) =>
                message.metadata['memory_retrieval_status']?.toString() ==
                SemanticMemoryRetrievalStatus.unavailable.name,
          )
        ? SemanticMemoryRetrievalStatus.unavailable
        : memoryMessages.any(
            (message) =>
                message.metadata['memory_retrieval_status']?.toString() ==
                SemanticMemoryRetrievalStatus.degraded.name,
          )
        ? SemanticMemoryRetrievalStatus.degraded
        : SemanticMemoryRetrievalStatus.success;
    final memoryReason = memoryMessages.isEmpty
        ? 'no_semantic_memory_matches'
        : memoryMessages.first.metadata['memory_retrieval_reason']?.toString() ??
            'memory_retrieval_success';
    final modelIdUsed = memoryMessages.isEmpty
        ? 'none'
        : memoryMessages.first.metadata['embedding_model_id_used']?.toString() ??
            'none';
    final skippedCrossModelCount = memoryMessages.isEmpty
        ? 0
        : (memoryMessages.first.metadata['excluded_cross_model_matches']
                as int?) ??
            0;
    final standingOrders = await _standingOrderProvider.loadStandingOrders(
      sessionKey: sessionKey,
      maxTokens: plan.tokenAllocation.sectionBudgets['standing_orders'] ?? 0,
    );

    return RetrievedContextSources(
      memoryIndexBlock: memoryIndexBlock,
      memoryMessages: memoryMessages,
      standingOrders: standingOrders,
      workflowContext: plan.workflowContext,
      memoryRetrievalStatus: memoryStatus,
      memoryRetrievalReason: memoryReason,
      embeddingModelIdUsed: modelIdUsed,
      skippedCrossModelCount: skippedCrossModelCount,
    );
  }
}
