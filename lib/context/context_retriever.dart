import 'package:openreef/context/compiled_context_package.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/memory/memory_index.dart';

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
    final standingOrders = await _standingOrderProvider.loadStandingOrders(
      sessionKey: sessionKey,
      maxTokens: plan.tokenAllocation.sectionBudgets['standing_orders'] ?? 0,
    );

    return RetrievedContextSources(
      memoryIndexBlock: memoryIndexBlock,
      memoryMessages: memoryMessages,
      standingOrders: standingOrders,
      workflowContext: plan.workflowContext,
    );
  }
}
