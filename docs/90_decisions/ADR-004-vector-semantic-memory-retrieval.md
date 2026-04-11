### Target State
Replace the current heuristic assembler with a **production-grade Context Compiler** that converts runtime state into a structured, policy-driven compiled context package.

Target model:

```text
ExecutionRequest + SessionState + WorkflowState + RuntimePolicies
    ->
CompiledContextPackage
The ContextAssembler should be split into two major responsibilities:

1.  **Context Planning**
    
    *   decide what the model should see
        
    *   decide execution mode
        
    *   decide which tools are exposed
        
    *   decide which memory/history/workflow/tool-state items are included
        
    *   decide token allocation
        
    *   decide whether compaction is recommended/required
        
    *   enforce safety/confirmation policies
        
2.  **Context Rendering**
    
    *   render structured prompt sections
        
    *   serialize tools, memory, skills, workflow state, history, and user message
        
    *   emit an auditable compiled context package
        

### Required Redesign Structure

#### 1\. Replace flat assembly with modular architecture

`   ContextAssembler ├── ContextPlanner │    ├── TurnClassifier │    ├── ExecutionModeResolver │    ├── SafetyPolicyEvaluator │    ├── ToolExposurePlanner │    ├── MemoryRetrievalPlanner │    ├── HistoryPlanner │    ├── SkillPlanner │    ├── WorkflowStatePlanner │    └── TokenBudgetPlanner │ ├── ContextRetriever │    ├── MemoryRetriever │    ├── StandingOrderRetriever │    ├── WorkflowStateRetriever │    ├── FileStateRetriever │    └── RecentToolStateRetriever │ ├── ContextReducer │    ├── HistoryReducer │    ├── MemoryReducer │    ├── ToolResultReducer │    ├── EvidenceDeduplicator │    └── CompactionReducer │ ├── ContextRenderer │    ├── SystemPromptRenderer │    ├── ToolSchemaRenderer │    ├── MemoryRenderer │    ├── WorkflowRenderer │    ├── HistoryRenderer │    └── FinalMessageRenderer │ └── ContextAudit      ├── assembly trace      ├── section token usage      ├── selected vs dropped items      └── policy decisions   `

#### 2\. Replace AssembleResult with a richer compiled package

`   class CompiledContextPackage {  final CompiledPrompt prompt;  final ContextPlan plan;  final ToolExposure toolExposure;  final MemorySelection memorySelection;  final HistorySelection historySelection;  final WorkflowContext workflowContext;  final TokenAllocation tokenAllocation;  final SafetyEnvelope safetyEnvelope;  final ContextAuditTrace auditTrace;  final bool compactRequested;  final bool compactRecommended;  final ExecutionMode executionMode;}   `

#### 3\. Add explicit execution mode

Context shape must vary by mode.

`   enum ExecutionMode {  chat,  reactiveToolUse,  workflowContinuation,  standingOrderExecution,  triggerExecution,  confirmationPending,  recoveryAfterToolFailure,  compactionRecovery,}   `

#### 4\. Replace centroid intent detection with real turn classification

Target output:

`   class TurnClassification {  final String domain;  final String taskType;  final bool likelyNeedsTools;  final bool likelyNeedsMemory;  final bool likelyNeedsWorkflowState;  final bool likelyNeedsUserConfirmation;  final bool likelyMultiStep;  final double confidence;}   `

Preferred approach:

*   deterministic rules first
    
*   model-based classifier for ambiguous cases
    

#### 5\. Replace similarity-based tool selection with policy-based tool exposure

Tool exposure should consider:

*   execution mode
    
*   domain/task type
    
*   tool capabilities
    
*   preconditions
    
*   confirmation requirements
    
*   safety constraints
    
*   workflow stage
    

Target shape:

`   class ToolExposure {  final List primaryTools;  final List fallbackTools;  final List excludedToolIds;  final Map exclusionReasons;}   `

Each tool should expose a capability profile:

`   class ToolCapabilityProfile {  final String id;  final List domains;  final List actions;  final bool readOnly;  final bool destructive;  final bool requiresConfirmation;  final bool requiresUserIdentity;  final bool requiresFileScope;  final bool longRunning;  final bool expensive;  final bool requiresWorkflowState;  final Set allowedModes;  final ToolArgumentSchema schema;}   `

#### 6\. Introduce multi-class memory planning and ranking

Memory must become multi-channel:

*   episodic memory
    
*   semantic memory
    
*   procedural memory
    
*   working memory
    

Target plan:

`   class MemoryRetrievalPlan {  final bool fetchSemantic;  final bool fetchEpisodic;  final bool fetchProcedural;  final bool fetchWorking;  final int semanticBudget;  final int episodicBudget;  final int proceduralBudget;  final int workingBudget;}   `

Ranking should combine:

*   semantic relevance
    
*   recency
    
*   importance
    
*   task continuity
    
*   duplication penalty
    
*   contradiction penalty
    

#### 7\. Add workflow state as first-class context

Do not force the model to reconstruct multi-step state from raw history.

`   class WorkflowContext {  final String? workflowId;  final String? objective;  final List completedSteps;  final List pendingSteps;  final List blockers;  final Map artifacts;  final Map resolvedEntities;  final String? currentHypothesis;}   `

#### 8\. Replace naive newest-first history slicing with structural history planning

History selection should preserve:

*   task root/objective
    
*   latest user constraints
    
*   confirmation outcomes
    
*   relevant recent tool outcomes
    
*   unresolved questions
    
*   current subtask turns
    

Prefer dropping:

*   repetitive assistant chatter
    
*   stale failed tool logs
    
*   superseded results
    
*   low-signal history
    

#### 9\. Add dedicated ToolResultReducer

Raw tool outputs should not sit in prompt context unless strictly necessary.

Target behavior:

*   normalize tool outputs into summaries
    
*   preserve artifact references instead of raw blobs
    
*   classify results as keep / summarize / discard
    

Example summary shape:

`   TOOL RESULT SUMMARYtool: file_searchstatus: successkey findings:- Found 3 matching files- Most recent file is budget_final.xlsxartifact_refs:- file://budget_final.xlsx   `

#### 10\. Replace pattern-based skill gating with policy-driven skill planning

Skills should be activated using:

*   task type
    
*   workflow stage
    
*   execution mode
    
*   failure patterns
    
*   artifact type
    
*   domain policy
    

Target shape:

`   class SkillDefinition {  final String id;  final String displayName;  final String instructionBlock;  final ActivationPolicy activationPolicy;  final List requiredToolIds;  final Set allowedModes;  final int priority;  final int maxTokens;  final List incompatibleSkillIds;}   `

#### 11\. Make token budgeting adaptive

Replace static ratio budgeting with dynamic allocation based on:

*   execution mode
    
*   task complexity
    
*   workflow continuation state
    
*   expected output size
    
*   memory/history/tool-state mix
    
*   compaction pressure
    

#### 12\. Add compaction policy engine

Compaction must become policy-driven, not just externally requested.

Need:

*   compactRecommended
    
*   compactRequired or equivalent policy signal
    

Triggers should include:

*   sustained high budget usage
    
*   excessive stale tool state
    
*   repeated overflow pressure
    
*   context entropy growth
    

Compaction output should preserve:

*   resolved steps
    
*   unresolved blockers
    
*   retained constraints
    
*   retained artifact refs
    
*   dropped section trace
    

#### 13\. Add safety envelope to context planning

Target shape:

`   class SafetyEnvelope {  final bool confirmationRequired;  final List riskyToolIds;  final List forbiddenToolIds;  final List warningInstructions;  final List hardConstraints;}   `

#### 14\. Render prompt as structured sections, not flat string assembly

Target prompt structure:

`   [SYSTEM IDENTITY][EXECUTION MODE][SAFETY RULES][WORKFLOW STATE][AVAILABLE TOOLS][ACTIVE SKILLS][STANDING ORDERS][RELEVANT MEMORY][RECENT RELEVANT HISTORY][PREVIOUS TOOL STATE][USER MESSAGE]   `

Each section should be:

*   independently measurable
    
*   independently droppable
    
*   independently compressible
    
*   included/excluded with traceable reasons
    

#### 15\. Add full assembly auditability

Target shape:

`   class ContextAuditTrace {  final List includedSectionIds;  final List droppedSectionIds;  final Map sectionTokenUsage;  final Map inclusionReasons;  final Map exclusionReasons;  final List policyDecisions;}   `

This is required for debugging:

*   why memory was included/excluded
    
*   why tools were exposed/hidden
    
*   why compaction triggered
    
*   why critical context was dropped
    

### Acceptance Criteria

*   Context assembly output is no longer just a flat prompt/message list
    
*   Execution mode is explicitly resolved and carried through assembly
    
*   Tool exposure is policy-based, capability-aware, and auditable
    
*   Memory retrieval is multi-class and ranking-aware
    
*   Workflow state is included as first-class context when relevant
    
*   History selection is structural, not just newest-first
    
*   Tool results are summarized/reduced before context injection
    
*   Skill activation is policy-driven, not regex/pattern-only
    
*   Token allocation is adaptive
    
*   Compaction recommendation is policy-driven
    
*   Final compiled context includes audit trace and section-level token accounting
    

### Suggested Implementation Phases

#### Phase 1

*   add ExecutionMode
    
*   add TurnClassification
    
*   replace centroid intent routing
    
*   replace AssembleResult with CompiledContextPackage
    

#### Phase 2

*   add ToolExposurePlanner
    
*   add HistoryPlanner
    
*   add ToolResultReducer
    
*   add ContextAuditTrace
    

#### Phase 3

*   add workflow state as first-class context
    
*   add adaptive token planner
    
*   add compaction policy engine
    
*   add policy-based skill planning
    

#### Phase 4

*   add multi-class memory retrieval/ranking
    
*   add safety envelope policy layer
    
*   move to structured section-based rendering
    

### Final Note

This is not a cosmetic refactor. This is a runtime architecture correction.

The current ContextAssembler is good enough for MVP prompt assembly, but not good enough for:

*   persistent workflows
    
*   reliable tool loops
    
*   long-lived sessions
    
*   trigger-driven execution
    
*   recovery-heavy agent behavior
    

Until this is fixed, the agent runtime remains structurally fragile.

## Related Documents
- [Memory Architecture](../04_context-memory/memory-architecture.md)
- [Context Assembly](../04_context-memory/context-assembly.md)
