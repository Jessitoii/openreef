[Base preserved from review-gap-tracker.md]

GAP-001: Multiple Runtime Paths
Status: CLOSED

GAP-002: Broken Agent Loop
Status: CLOSED

GAP-003: Weak Memory System
Status: CLOSED

GAP-004: Skills Not Integrated
Status: CLOSED

GAP-005: Trigger System Incomplete
Status: CLOSED

GAP-006: MCP Not Integrated
Status: CLOSED

GAP-007: Missing Approval Flow
Status: CLOSED

GAP-008: UI Misalignment
Status: OPEN
Priority: HIGH
Area: Product Surface

### Problem

UI surfaces imply capabilities that are not operational in runtime.

### Current Behavior

Skills, MCP, voice, and automation appear functional in UI but are not wired into runtime execution.

### Why Insufficient

Creates false expectations and silent failures.

### Target Behavior

UI must strictly reflect runtime truth and capability maturity.

---

GAP-011: Voice Pipeline Not Runnable
Status: OPEN
Priority: MEDIUM
Area: Voice

### Problem

End-to-end voice pipeline is not executable.

### Current Behavior

Wake detection, STT, and TTS exist partially but are not connected.

### Why Insufficient

Feature appears usable but does nothing.

### Target Behavior

Either fully runnable pipeline or clearly marked experimental.

---

GAP-012: AutoDream Not Operational
Status: OPEN
Priority: MEDIUM
Area: Background Memory

### Problem

AutoDream is present in code but not executed in runtime.

### Current Behavior

Worker exists but not scheduled or triggered.

### Why Insufficient

Misleading architecture; feature is effectively dead.

### Target Behavior

Either fully operational or explicitly removed from MVP.

---

GAP-013: Final Agent Response Not Visible
Status: CLOSED
Severity: CRITICAL
Area: Agent Runtime / UI Integration

### Closure Notes




### Problem

Agent produces final responses but they are not reliably surfaced to the UI.

### Current Behavior

Streaming or intermediate steps may appear, but final resolved output is missing or inconsistent.

### Why Insufficient

Breaks core product contract: user cannot see agent result.

### Target Behavior

Every execution must produce a deterministic final visible response in UI.

---

GAP-014: ContextAssembler Heuristic-Based
Status: CLOSED
Severity: HIGH
Agent Runtime / Context Assembly / Execution Reliability

### Current State
`ContextAssembler` currently handles:
- intent detection
- tool selection
- skill gating
- memory retrieval
- standing order retrieval
- history slicing
- token budgeting
- final message assembly

This is enough for MVP-level prompt construction, but the design is still fundamentally a heuristic prompt packer rather than a production-grade context policy engine.

Current weaknesses:
- intent detection is centroid-based and too weak for reliable routing
- tool selection is embedding-similarity-driven rather than policy/schema-aware
- skill activation is pattern-trigger based and brittle
- history selection is mostly newest-first token slicing
- memory retrieval is not clearly multi-class, ranked, or continuity-aware
- tool results are not reduced aggressively enough into structured summaries
- workflow state is not first-class context
- execution mode is not explicit
- token allocation is static rather than adaptive
- compaction is externally requested, not policy-driven
- context assembly lacks auditability and deterministic policy traces

### Why This Matters
This gap directly affects:
- multi-step reliability
- tool misuse prevention
- long-session quality
- workflow continuation
- compaction safety
- failure recovery
- debugging and observability
- context budget efficiency

If left as-is, the agent will remain “working but fragile”:
- more hallucination under long context
- unnecessary tool exposure
- stale or irrelevant history pollution
- weak recovery after failed tool calls
- poor scaling to persistent workflows and trigger-driven execution

### Closure Notes



---

GAP-015: Missing unified execution lifecycle model for ephemeral and persistent tasks
Status: CLOSED
Severity: HIGH
Area: Execution Runtime / Workflow / Automation

### Current State

OpenReef has an agent loop, tool routing, and trigger-based execution, but lacks a unified execution lifecycle model.

Currently:
- chat executions are ephemeral and implicit
- trigger executions are partially modeled
- automation behavior is simulated through prompt-driven logic

There is no explicit distinction between:
- short-lived execution
- persisted, resumable execution

There is also no consistent representation of:
- run state
- suspend/resume behavior
- execution policy
- lifecycle transitions

### Why This Matters

Without an explicit lifecycle model:

- automation becomes prompt-driven instead of state-driven
- suspend/resume behavior is unclear and fragile
- execution policy (retry, timeout, duplicate control) is inconsistent
- chat and automation semantics blur together
- debugging and replay are weak or impossible
- future automation features will be bolted onto the loop ad hoc

### Target State

The system uses a **single execution engine and loop**, while explicitly modeling execution lifecycle.

Execution must be:

- classified into lifecycle-based modes (ephemeral, persistent, resume, triggered)
- governed by explicit execution policy
- backed by persisted run state for long-lived tasks
- unified across chat, triggers, and resumable execution paths

Lifecycle semantics must be represented in state, not inferred from prompts.

### In Scope

- unified execution request model
- execution mode classification
- policy-driven execution behavior
- persisted run state for long-lived execution
- suspend/resume lifecycle modeling
- shared execution loop across all execution paths

### Out of Scope

- DAG orchestration
- distributed workflow engine
- parallel execution graphs
- nested workflows
- full BPM system

### Closure Criteria

This gap is closed when:

- execution is classified into explicit lifecycle modes
- all execution paths (chat, trigger, resume) use the same executor
- a shared execution loop is used across all modes
- execution behavior is governed by explicit policy (not prompt logic)
- persistent runs have explicit stored run state and lifecycle status
- suspend/resume behavior is modeled via state transitions
- execution results are structured and inspectable (not just chat output)

### Closure Notes

The execution runtime now uses a single `AgentTaskExecutor` entry path with explicit lifecycle classification, durable run state, structured `ExecutionResult`, and state-driven resume inputs. Persistent runs store lifecycle status, transitions, continuation state, waiting metadata, and standing-order evaluations, so workflow-style behavior is no longer reconstructed from prompt text.

---

GAP-016: No Execution Policy
Status: CLOSED
Severity: CRITICAL
Area: Execution System

### Problem

No clear policy for queuing, preemption, or rejection of tasks.

### Current Behavior

Execution behavior is undefined under concurrency.

### Why Insufficient

Leads to race conditions and unpredictable agent behavior.

### Target Behavior

Explicit execution policy (queueing, prioritization, cancellation).

### Closure Notes

Execution policy is now enforced at the executor and loop boundaries instead of being descriptive only. The runtime applies queue / reject / replace-running behavior, duplicate suppression, coalescing, cancellation-backed supersession, timeout limits, max-step limits, and max-tool-call limits through the shared execution path.

---

GAP-017: Tool pipeline is wired but tool execution is failing at runtime

Status: CLOSED

Severity: Critical

Area: Tool Runtime / Dispatch / Integration Reliability

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

### Closure Notes



---

GAP-018: Built-in Skills Not Injected
Status: CLOSED
Severity: HIGH
Area: Skills Runtime

### Problem

Built-in skills are not automatically injected into context.

### Current Behavior

Skills require manual or implicit activation.

### Why Insufficient

Skills system remains underutilized.

### Target Behavior

Automatic skill discovery and injection based on relevance.

### Closure Notes



---

GAP-019: MCP / Skills / Trigger UI Surfaces Incomplete
Status: OPEN
Severity: HIGH
Area: Product Surface

### Problem

Core capability surfaces are incomplete or misleading.

### Current Behavior

UI exists but lacks full lifecycle (install, enable, debug, state).

### Why Insufficient

Users cannot manage or trust system capabilities.

### Target Behavior

Complete lifecycle UX for all capability systems.

---

GAP-020: Multimodal Composer Missing
Status: OPEN
Severity: MEDIUM
Area: Input System

### Problem

No unified multimodal input composition layer.

### Current Behavior

Inputs are limited to text; no structured multimodal handling.

### Why Insufficient

Limits future extensibility and capability.

### Target Behavior

Composable multimodal input system (text, voice, files, etc.).

---

GAP-021: Model Capability Gating Missing
Status: OPEN
Severity: HIGH
Area: Model System

### Problem

No gating between model capabilities and UI/runtime features.

### Current Behavior

All features appear available regardless of model support.

### Why Insufficient

Leads to invalid executions and poor UX.

### Target Behavior

Capability-aware routing and UI gating.

---

GAP-022: Model Marketplace State Broken
Status: OPEN
Severity: MEDIUM
Area: Model Management

### Problem

Model install/download/state is inconsistent.

### Current Behavior

Model state not reliably reflected in UI/runtime.

### Why Insufficient

Users cannot trust model availability.

### Target Behavior

Single source of truth for model state.

---

GAP-023: Streaming & Multi-step Visibility Missing
Status: OPEN
Severity: HIGH
Area: UI / Agent Runtime

### Problem

User cannot clearly see multi-step execution progress.

### Current Behavior

Partial streaming exists but lacks structured visibility.

### Why Insufficient

Reduces trust and debuggability.

### Target Behavior

Clear step-by-step execution visualization.

---

GAP-024: Chat Workspace UX Debt
Status: OPEN
Severity: MEDIUM
Area: UX

### Problem

Chat workspace lacks clarity, control, and state visibility.

### Current Behavior

Limited controls and unclear system state.

### Why Insufficient

Prevents power-user workflows.

### Target Behavior

Professional-grade workspace with full control and observability.
