# OpenReef GAP Discovery

## Purpose

This document is the raw discovery ledger for newly identified gaps in OpenReef.

It is **not** the execution tracker.

Use this file to:

* capture newly discovered structural, runtime, UI, and product gaps
* describe why each gap matters
* define a concrete target state
* prepare gaps for later merge into `gap_review_tracker.md`

Use `gap_review_tracker.md` to:

* track status
* assign phases
* record implementation progress
* close items

---

## Discovery Rules

1. One gap per real failure surface.
2. Do not mix architecture corrections with UI polish unless the UI issue is blocking runtime visibility or user trust.
3. A gap is valid only if it has:

   * current state
   * impact
   * target state
   * rough implementation direction
4. Duplicate gaps should be merged, not rephrased.

---

## GAP-001: Final assistant response is generated but not rendered reliably in chat

### Status

CLOSED

### Severity

Critical

### Area

UI / Chat Session / Runtime Result Delivery

### Current State

The most likely cause of the user not seeing the agent response is that `AgentLoopChatSession.sendMessage()` or its downstream completion path does not append the final assistant message into the visible transcript.

Observed failure shape:

* agent loop appears to complete
* logs show token emission or a final response exists
* final assistant text is not visible in the chat thread

Most likely failure points:

* final text exists in `AgentLoopResult` but is never converted into a `ChatMessage`
* `ChatMessage` is created but appended to stale or wrong session state
* repository persistence succeeds but UI controller does not emit updated state
* state emission happens before append/merge completes
* non-standard execution paths such as workflow/trigger/system results are filtered from visible chat
* streaming/final merge logic drops the final assistant message

### Why This Matters

This is not cosmetic. This makes the core product look broken.

If the agent thinks, streams, uses tools, and completes but the user sees nothing, then:

* trust collapses
* debugging gets misleading
* workflow execution appears fake
* tool success looks like failure
* the whole chat surface becomes unreliable

### Target State

All successful execution paths must write through one unified visible message pipeline.

Required behavior:

* final assistant output is always converted into a visible message
* message is persisted before completion state is emitted
* workflow/trigger/manual executions all use the same append path
* streaming tokens progressively update the visible assistant bubble
* finalization merges into that bubble instead of replacing or dropping it
* session ID integrity is asserted across executor, repository, controller, and UI layers

### Required Fix Direction

Instrument each boundary with session ID and message count delta:

* executor boundary
* result packaging boundary
* repository persistence boundary
* controller emission boundary
* renderer binding boundary

Likely hot files:

* `lib/ui/agent_loop_chat_session.dart`
* `lib/ui/chat_workspace_controller.dart`
* session repository sync boundary

---

## GAP-002: ContextAssembler is still heuristic prompt assembly, not a production-grade context compiler

### Status

Open

### Severity

High

### Area

Agent Runtime / Context Assembly / Execution Reliability

### Current State

`ContextAssembler` currently handles too many responsibilities in one heuristic assembly path:

* intent detection
* tool selection
* skill gating
* memory retrieval
* standing order retrieval
* history slicing
* token budgeting
* final prompt/message assembly

This is enough for MVP prompt packing, but not enough for a robust agent runtime.

Current weaknesses:

* intent detection is centroid-based and weak for reliable routing
* tool selection is embedding-similarity-driven instead of policy/schema-aware
* skill activation is brittle pattern triggering
* history selection is mostly newest-first token slicing
* memory retrieval is not clearly multi-class, ranked, or continuity-aware
* tool results are not aggressively reduced into structured summaries
* workflow state is not first-class context
* execution mode is not explicit
* token allocation is static instead of adaptive
* compaction is externally requested instead of policy-driven
* assembly decisions are not auditable

### Why This Matters

This gap directly harms:

* multi-step reliability
* tool correctness
* long-session quality
* workflow continuation
* failure recovery
* observability
* token efficiency

If left like this, the runtime remains working but fragile.

### Target State

Replace the heuristic assembler with a **Context Compiler** that produces a structured `CompiledContextPackage` from runtime state and policy.

Target responsibilities:

* explicit context planning
* explicit context retrieval
* context reduction before injection
* structured rendering by section
* policy trace and auditability
* explicit execution mode
* first-class workflow context
* adaptive token allocation
* policy-driven compaction

### Required Redesign Structure

```text
ContextAssembler
 ├── ContextPlanner
 │    ├── TurnClassifier
 │    ├── ExecutionModeResolver
 │    ├── SafetyPolicyEvaluator
 │    ├── ToolExposurePlanner
 │    ├── MemoryRetrievalPlanner
 │    ├── HistoryPlanner
 │    ├── SkillPlanner
 │    ├── WorkflowStatePlanner
 │    └── TokenBudgetPlanner
 │
 ├── ContextRetriever
 ├── ContextReducer
 ├── ContextRenderer
 └── ContextAudit
```

### Acceptance Markers

* assembly output is no longer just a flat prompt/message list
* execution mode is explicit
* tool exposure is policy-based and auditable
* workflow state is first-class when relevant
* history planning is structural
* tool results are reduced before injection
* skill activation is policy-driven
* compaction recommendation is policy-driven
* final compiled context includes audit trace and section token accounting

### Suggested Phases

Phase 1:

* add `ExecutionMode`
* add `TurnClassification`
* replace centroid intent routing
* replace `AssembleResult` with richer compiled package

Phase 2:

* add `ToolExposurePlanner`
* add `HistoryPlanner`
* add `ToolResultReducer`
* add `ContextAuditTrace`

Phase 3:

* add workflow state as first-class context
* add adaptive token planning
* add compaction policy engine
* add policy-based skill planning

Phase 4:

* add multi-class memory retrieval and ranking
* add safety envelope
* move to structured section rendering

---

GAP-003: Workflow layer lacks explicit lifecycle-bound persistent execution model
---------------------------------------------------------------------------------

### Status

CLOSED

### Severity

High

### Area

Automation / Workflow Runtime / Execution Lifecycle

### Problem

OpenReef has a working execution engine (AgentTaskExecutor + loop), trigger system, and tool routing, but it still lacks a **properly integrated persistent execution layer aligned with the unified execution model**.

The issue is not absence of execution capability.

The issue is:

👉 **workflow/persistent execution is not modeled as a first-class lifecycle within the unified execution system**

What is missing is not a large workflow engine, but:

*   lifecycle-aware persistent execution (persistent\_request, resume\_request, triggered\_request)
    
*   explicit WorkflowRun ↔ RunState mapping into execution runtime
    
*   deterministic step progression that survives suspend/resume
    
*   variable/state binding independent of prompt reconstruction
    
*   executor-level ownership of workflow continuation (not loop improvisation)
    
*   policy-driven control for concurrency, duplication, retry, and suspension
    

Right now, automation exists conceptually, but execution semantics are still partially implicit and prompt-driven.

### Current Behavior

*   Agent loop can simulate multi-step behavior, but lacks explicit persistent lifecycle control
    
*   Trigger system can fire events, but execution is not always tied to a durable run model
    
*   Resume behavior is not consistently grounded in stored run state
    
*   Standing orders behave closer to prompt injection than lifecycle-bound execution
    
*   Execution classification (ephemeral vs persistent) is not enforced at intake level
    
*   Workflow-like behavior is partially embedded inside loop logic rather than modeled explicitly
    

### Why Insufficient

Without aligning workflow execution to the unified execution model:

*   persistent automation remains fragile and non-deterministic
    
*   suspend/resume behavior depends on prompt reconstruction instead of state
    
*   trigger-driven execution lacks consistent lifecycle ownership
    
*   debugging, replay, and observability are weakened
    
*   duplicate run control and concurrency behavior remain undefined
    
*   execution policy cannot be enforced cleanly at runtime boundaries
    
*   the system drifts toward prompt-driven orchestration instead of state-driven execution
    

### Target / Expected Behavior

Workflow execution must become a **first-class lifecycle mode inside the unified execution system**, not a separate runtime and not an emergent behavior inside the loop.

The correct target:

*   all execution flows through:
    
    *   ExecutionClassifier
        
    *   ExecutionRequest
        
    *   AgentTaskExecutor
        
    *   shared ExecutionLoop
        
*   lifecycle is explicit:
    
    *   ephemeral\_request
        
    *   persistent\_request
        
    *   resume\_request
        
    *   triggered\_request
        
*   persistent execution is backed by:
    
    *   WorkflowDefinition (static)
        
    *   WorkflowRun (live instance)
        
    *   RunState (authoritative state)
        
*   execution behavior is:
    
    *   state-driven
        
    *   policy-constrained
        
    *   resumable without prompt reconstruction
        
*   executor remains the single authority:
    
    *   no secondary workflow engine
        
    *   no parallel orchestration runtime
        

### Minimal Correct Design (Aligned with Unified Execution Model)

Support in v1:

*   sequential deterministic steps
    
*   basic conditional branching (ConditionExpr)
    
*   variable binding from previous step outputs
    
*   explicit suspend/resume points
    
*   trigger compatibility (triggered\_request)
    
*   optional LLM-backed steps (via structured execution, not freeform loop abuse)
    
*   persisted WorkflowRun with inspectable lifecycle state
    

Explicitly NOT supported in v1:

*   arbitrary loops
    
*   parallel branches
    
*   nested workflows
    
*   DAG orchestration engines
    
*   distributed execution systems
    

### Required Architecture

*   ExecutionClassifier
    
    *   determines lifecycle mode at intake
        
*   ExecutionRequest
    
    *   normalized input including mode, policy, and run context
        
*   AgentTaskExecutor
    
    *   single execution entry point
        
    *   loads RunState when needed
        
    *   applies policy
        
    *   invokes shared loop
        
*   ExecutionLoop (existing AgentLoop)
    
    *   remains the shared orchestration core
        
    *   does not own lifecycle semantics
        
*   WorkflowRunner (adapter, NOT a second runtime)
    
    *   deterministic step resolver
        
    *   translates workflow steps into loop actions
        
*   ToolRouter
    
    *   unchanged, still the only tool execution path
        
*   ExecutionResult
    
    *   must reflect lifecycle outcomes (run\_suspended, run\_resumed, etc.)
        

### Required New Models

*   WorkflowDefinition
    
*   WorkflowStep
    
*   ConditionExpr
    
*   WorkflowRun
    
*   WorkflowPolicy (optional extension of ExecutionPolicy)
    
*   WorkflowStepExecution
    
*   RunState (explicit lifecycle state, if not already formalized)
    

### Required New Files

*   lib/workflows/workflow\_definition.dart
    
*   lib/workflows/workflow\_run.dart
    
*   lib/workflows/workflow\_step.dart
    
*   lib/workflows/workflow\_store.dart
    
*   lib/workflows/workflow\_runner.dart
    
*   lib/workflows/workflow\_compiler.dart
    
*   lib/workflows/condition\_evaluator.dart
    

### Existing Files Likely Affected

*   lib/execution/execution\_request.dart
    
*   lib/execution/execution\_classifier.dart
    
*   lib/execution/agent\_task\_executor.dart
    
*   lib/execution/execution\_loop.dart (or existing agent\_loop.dart)
    
*   lib/agent/tool\_router.dart
    
*   lib/triggers/trigger\_system.dart
    
*   lib/triggers/trigger\_models.dart
    
*   lib/ui/agent\_loop\_chat\_session.dart
    
*   lib/ui/chat\_workspace\_controller.dart
    
*   existing persistence layers for sessions / run state
    

### Key Constraint

This gap must be solved **without introducing a second runtime**.

Violations:

*   ❌ separate workflow executor
    
*   ❌ separate workflow loop
    
*   ❌ workflow-only tool routing
    
*   ❌ prompt-driven fake persistence
    

Correct approach:

*   ✅ extend existing executor
    
*   ✅ reuse shared loop
    
*   ✅ make lifecycle explicit
    
*   ✅ persist real run state
    
*   ✅ keep system state-driven, not prompt-driven

### Closure Notes

This gap is closed by the unified execution lifecycle implementation in `lib/agent/`. The runtime now classifies requests into explicit lifecycle modes, persists run state durably, resumes from stored continuation state, and keeps all execution on the shared `AgentLoop` rather than introducing a second workflow runtime.

---

## GAP-004: Trigger and standing-order execution still lacks a clean execution policy layer

### Status

CLOSED

### Severity

High

### Area

Automation / Scheduler / Runtime Coordination

### Current State

Triggers exist conceptually and partially in implementation, but execution arbitration is still weak.

Missing pieces:

* executor-level concurrency policy
* per-workflow run policy
* duplicate suppression rules
* burst handling for MCP events
* coalescing behavior
* queue vs reject vs replace semantics
* standing orders as deterministic rules instead of prompt text injection

### Why This Matters

Without execution policy:

* triggers fight each other
* background tasks race with foreground chat
* duplicate automations pile up
* standing orders become unreliable and hard to debug
* the system cannot scale beyond toy automation

### Target State

Add:

* `ExecutionPolicy` at executor level
* `WorkflowConcurrencyPolicy` at workflow level
* standing orders as runtime-evaluated condition-action rules
* event-source-specific duplicate handling

Recommended MVP rules:

* user chat preempts queued background work in same session
* trigger workflows queue unless explicitly replace-running
* duplicate standing-order style runs reject if already active
* MCP event bursts coalesce by key when possible

### Closure Notes

Execution policy is now enforced in the executor instead of being implied in prompt text. Queue, reject, replace-running, duplicate suppression, coalescing, timeout, max-step, and max-tool-call semantics are implemented against durable run metadata, and standing orders are represented as structured runtime directives with persisted evaluation outcomes.

---

## GAP-005: Tool pipeline is wired but tool execution is failing at runtime

### Status

Open

### Severity

Critical

### Area

Tool Runtime / Dispatch / Integration Reliability

### Current State

The agent performs tool calling, but the tools do not actually execute successfully. The tool pipeline shape appears correct, but real runtime dispatch or integration is broken.

This means the architecture is claiming capabilities that are not delivered end to end.

Possible failure surfaces:

* manifest and runtime implementation mismatch
* argument schema mismatch
* permission/approval dead path
* MCP connection state mismatch
* async result propagation failure
* tool result not returned into loop context
* platform bridge failure on Android/native side

### Why This Matters

This is a product credibility failure.

If tool calling is visible but tool execution fails:

* automation is fake
* workflow layer cannot be trusted
* user mental model collapses
* debugging becomes noisy because reasoning path looks correct while effect path is dead

### Target State

Every exposed tool must pass an end-to-end execution contract:

* listed in registry
* invokable through router
* validates args
* enforces confirmation policy
* executes real implementation
* returns normalized result
* emits visible execution state
* injects reduced result back into context
* persists execution record

### Required Fix Direction

Create a tool validation matrix:

* tool ID
* manifest present
* implementation bound
* permission path works
* confirmation path works
* returns result
* result visible in loop
* result visible in UI step trace

Do not debug this abstractly. Prove each boundary per tool category.

---

## GAP-006: Built-in skills are not being injected into runtime context

### Status

Open

### Severity

High

### Area

Skills Runtime / Context Injection / Agent Capability Activation

### Current State

Built-in skills exist as an architectural concept, but they are not being injected into runtime context correctly.

This breaks one of the main product promises: the agent is supposed to selectively use skills, but in practice the runtime may not be exposing them when needed.

### Why This Matters

If skills do not enter context:

* specialized behavior disappears
* tool usage becomes dumber
* skill-creator loses strategic value
* behavior becomes inconsistent between design docs and runtime reality

### Target State

Built-in and user-installed skills must be:

* discoverable by registry
* enable/disable aware
* selectable by policy
* injectible into context as structured skill blocks
* auditable in context trace
* visible in UI as active/inactive/runtime-selected

### Required Fix Direction

Validate the full skill path:

* skill discovery
* metadata load
* enablement state
* selection/gating
* context rendering
* runtime audit trace

---

## GAP-007: MCP management UI is far below the planned connector model

### Status

Open

### Severity

Medium

### Area

UI / MCP / External Integrations

### Current State

The MCP page should expose recognizable connector-style server presets such as Gmail, Calendar, GitHub, Slack, Notion, and others, allowing the user to connect them directly.

Instead, the intended productized connector experience is missing or incomplete.

### Why This Matters

This is not just UI polish.

MCP is one of the core OpenReef capability layers. If the connector experience is weak:

* integrations feel unfinished
* onboarding friction explodes
* users cannot discover what the agent can actually connect to
* runtime capability feels hidden and inconsistent

### Target State

The MCP page must support:

* preset connector cards for major servers
* add/connect flow from UI
* connection health/state
* auth state visibility
* enabled/disabled state
* reconnect and disconnect actions
* event and tool visibility per server

### Notes

This gap aligns with the product direction where MCP is a first-class client layer with discoverable connected servers and settings UI.

---

## GAP-008: Skills management UI is missing real filesystem-backed CRUD and state control

### Status

Open

### Severity

Medium

### Area

UI / Skills / Power-User Capability

### Current State

Right now skill creation is framed mainly through the agent’s own skill-creator path. That is not enough.

The user must also be able to directly manage skills from the UI:

* create skill folder
* write/edit `SKILL.md`
* add resources/examples
* enable/disable skill
* delete skill
* inspect skill files

### Why This Matters

If users cannot manage skills directly:

* advanced workflows are blocked
* local-first extensibility becomes fake
* debugging skill behavior becomes painful
* the product is too dependent on agent-generated skill authoring

### Target State

Build a real Skills workspace page with:

* skill list
* create/edit/delete
* enable/disable toggle
* file tree for each skill package
* editor for `SKILL.md` and support files
* validation for required files and metadata

---

## GAP-009: Composer is missing multimodal attachment support and model capability gating

### Status

Open

### Severity

Medium

### Area

UI / Input Surface / Model Runtime Compatibility

### Current State

The prompt composer does not yet support proper attachment of:

* voice messages
* images
* documents

Also, not every model supports image/audio understanding. That means the UI cannot expose media input blindly. Capability gating must follow selected model support.

### Why This Matters

Without this:

* multimodal roadmap claims are fake in practice
* users can trigger invalid flows with incompatible models
* the composer does not match model/runtime truth

### Target State

The composer must:

* support attaching voice, image, and document inputs
* check selected model capability before enabling input modes
* downgrade gracefully when model lacks support
* explain unsupported input types clearly
* pass attachments into the correct runtime preprocessing path

---

## GAP-010: Model marketplace and model installation UX are incomplete and partially broken

### Status

Open

### Severity

High

### Area

UI / Models / Runtime Provisioning

### Current State

The model screen currently has serious product gaps:

* only limited public models are exposed cleanly
* Hugging Face token-based installation path is missing or incomplete
* users cannot cleanly install additional supported models through their own token
* downloaded models may still show `download model` because initialize state is patched/broken
* installation and initialization state are not represented correctly

### Why This Matters

Models are the execution substrate.

If model installation UX is broken:

* capabilities are artificially locked
* state becomes confusing
* runtime appears unreliable even when downloads succeed
* the product loses one of its strongest differentiators: local model choice

### Target State

The models page must support:

* public models
* auth-required models via user HF token
* install progress
* downloaded vs initialized vs active state
* correct CTA transitions
* capability badges
* validation against runtime support

### Notes

This is both runtime-state integrity and UI integrity, not just marketplace polish.

---

## GAP-011: Streaming and multi-step execution visibility are not surfaced as first-class UI events

### Status

Open

### Severity

High

### Area

UI / Agent Transparency / Execution Trace

### Current State

The runtime appears to emit token-by-token logs, but the UI only shows the final message after completion.

Likewise, multi-step execution is not visible as a modern step trace. The user cannot see:

* searching
* fetching
* routing
* trigger creation
* schedule creation
* skill loading
* tool execution
* result shaping

This makes the agent feel opaque and much less capable than it actually is.

### Why This Matters

For an agent product, visibility is part of the product.

Without execution trace UI:

* multi-step capability feels fake
* tool use feels like a black box
* failures are harder to trust and debug
* the user cannot distinguish thinking, routing, and action

### Target State

Add first-class execution events to the visible chat thread:

* live token streaming into assistant bubble
* collapsible step blocks
* inline loading states
* tool step cards with lower-contrast modern styling
* clear transition from working steps to final answer
* same pattern for trigger/workflow/schedule flows

Example visible structure:

* Searching the web

  * `web_search` running
  * `web_fetch` running
* Reading skill instructions
* Sending SMS
* Done

This must be event-driven from runtime state, not faked by string templating.

---

## GAP-012: Chat workspace UX is wasting critical space and still behaves like a prototype

### Status

Open

### Severity

Medium

### Area

UI / Chat / Product Polish

### Current State

Several UI choices are actively hurting usability:

* drawer navigation sits too low and is buried under chats
* composer height is too large
* send button uses large text instead of proper icon treatment
* chat delete/rename actions are missing
* a large top card wastes vertical space with low-value status text
* overall visual language is still too terminal-heavy and not yet modern enough for a polished consumer product

### Why This Matters

This is not the highest architecture gap, but it is still real.

A cramped or clumsy chat UI makes a powerful runtime feel cheap.

### Target State

The chat workspace should move toward a modern professional interface while preserving the Claude-Code-inspired color identity.

Required outcomes:

* compact composer
* proper send icon
* remove wasteful top card
* chat rename/delete actions
* move navigation to a stronger top placement
* adopt better spacing, animation, elevation, and hierarchy

### Note

This gap should stay below execution correctness, runtime visibility, and workflow architecture in priority.

---

## GAP-013: Trigger and schedule management are not exposed as complete user-managed surfaces

### Status

Open

### Severity

Medium

### Area

UI / Automation / Trigger Management

### Current State

The product needs first-class trigger and schedule management surfaces from the main navigation, but those controls are missing or incomplete.

Users should be able to:

* view triggers
* view schedules
* create them
* edit them
* delete them
* enable/disable them
* inspect last run / next run / status

### Why This Matters

Automation that cannot be inspected or managed is not trustworthy.

### Target State

Expose dedicated Trigger and Schedule screens in navigation with:

* list views
* status badges
* create/edit/delete
* enable/disable
* execution metadata
* linkage to workflows or task targets

---

## Merge Guidance for `gap_review_tracker.md`

When merging discovery into the tracker:

1. Merge `GAP-001` and `GAP-011` only if the root cause is proven to be the same pipeline defect.

   * If final message delivery is broken and step streaming is also broken for the same transcript path, merge.
   * If final append works but step events are absent, keep separate.

2. Keep `GAP-002`, `GAP-003`, and `GAP-004` separate.

   * They touch related runtime territory, but they are not the same defect.

3. Keep `GAP-005` separate from all UI gaps.

   * Tool execution failure is a core runtime integrity gap.

4. Keep `GAP-007`, `GAP-008`, `GAP-009`, `GAP-010`, `GAP-012`, and `GAP-013` as product-surface gaps unless code review proves a common shared root cause.

---

## Priority Order

Recommended implementation priority:

1. `GAP-001` — final assistant response not visible
2. `GAP-005` — tool execution fails at runtime
3. `GAP-011` — streaming and multi-step visibility missing
4. `GAP-003` — workflow layer missing
5. `GAP-004` — execution policy and standing-order correctness
6. `GAP-002` — ContextAssembler redesign
7. `GAP-006` — built-in skills not injected
8. `GAP-010` — model marketplace/install state broken
9. `GAP-009` — multimodal composer + capability gating
10. `GAP-007` / `GAP-008` / `GAP-013` — MCP, Skills, Trigger/Schedule product surfaces
11. `GAP-012` — workspace polish and layout cleanup

---

## Final Verdict

Some of these are polish gaps.
Some are architecture gaps.
Some are outright credibility gaps.

The dangerous ones are not the pretty UI items.
The dangerous ones are:

* invisible final responses
* broken tool execution
* fake-looking multi-step execution
* lack of deterministic workflow runtime
* heuristic context assembly that will crack under scale

Fix those first.
Then make it beautiful.
