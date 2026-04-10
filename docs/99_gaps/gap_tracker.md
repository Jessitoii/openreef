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
Status: OPEN
Severity: CRITICAL
Area: Agent Runtime / UI Integration

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
Status: OPEN
Severity: HIGH
Area: Context System

### Problem

Context assembly relies on heuristics instead of a structured, policy-driven system.

### Current Behavior

Context is inconsistently constructed; important signals may be missing.

### Why Insufficient

Leads to unstable agent reasoning and unpredictable behavior.

### Target Behavior

Deterministic, policy-based context assembly with clear inputs/outputs.

---

GAP-015: Missing unified execution lifecycle model for ephemeral and persistent tasks
Status: OPEN
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

---

GAP-016: No Execution Policy
Status: OPEN
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

---

GAP-017: Tool Runtime Failures Not Standardized
Status: OPEN
Severity: HIGH
Area: Tooling

### Problem

Tool failures are not consistently handled or normalized.

### Current Behavior

Different tools fail in different ways.

### Why Insufficient

Agent cannot reason about failures reliably.

### Target Behavior

Standardized tool result schema with explicit failure modes.

---

GAP-018: Built-in Skills Not Injected
Status: OPEN
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
