# ADR-00X: Adopt a unified execution engine with lifecycle-specific execution modes

## Status

Accepted

## Context

OpenReef needs to support both immediate conversational interactions and long-lived automation.

The system already has:

* an agent loop
* tool routing
* trigger-based execution
* session-based chat handling

However, it lacks a consistent execution lifecycle model that can represent:

* short-lived ephemeral requests
* persistent automation
* resumable execution
* trigger-driven continuation

Without an explicit model, these behaviors risk being implemented through prompt-driven logic inside the agent loop. This leads to:

* non-deterministic behavior
* weak inspectability
* unclear suspend/resume semantics
* fragmented execution policy
* increasing architectural drift as features expand

The system needs a way to support automation without introducing a separate workflow runtime that would duplicate execution behavior.

## Decision

We adopt a unified execution model with the following properties:

* A **single execution engine** (`AgentTaskExecutor`) is used for all execution.
* A **shared orchestration loop** (`ExecutionLoop`) handles all execution paths.
* Execution is classified into explicit **lifecycle-based modes**:

  * `ephemeral_request`
  * `persistent_request`
  * `resume_request`
  * `triggered_request`
* Execution behavior is controlled through an explicit **ExecutionPolicy**, not implicit prompt logic.
* Long-lived automation is represented through **persisted run state** (`RunState`, `WorkflowRun`).
* Workflow structure is represented separately from execution via:

  * `WorkflowDefinition` (static)
  * `WorkflowRun` (live instance)

All execution—chat, triggers, and resumable runs—flows through the same executor and loop.

Lifecycle semantics are explicit and must not be inferred from prompts.

## Consequences

### Positive

* One execution engine simplifies system behavior and reduces duplication.
* Tool execution, logging, cancellation, and completion semantics remain consistent.
* Persistent automation becomes explicit, inspectable, and debuggable.
* Suspend/resume behavior is modeled in state rather than reconstructed from prompts.
* The system can evolve toward automation without introducing a second runtime.
* Clear separation between lifecycle (mode) and behavior (policy).

### Negative

* Requires explicit modeling of run state and lifecycle transitions.
* Adds upfront architectural complexity compared to a purely prompt-driven loop.
* ExecutionClassifier must be carefully designed to avoid ambiguity.
* Policy boundaries must remain strict to prevent logic leaking into prompts.
* More storage and state management is required for persistent runs.

## Alternatives Considered

### 1. Separate conversational runtime and workflow runtime

Rejected.

This would split execution semantics across two systems and lead to divergence in:

* tool behavior
* cancellation logic
* logging
* retry semantics
* completion handling

It would increase maintenance cost and introduce long-term inconsistency.

### 2. Pure agent loop with no explicit lifecycle distinction

Rejected.

Allowing the agent loop to implicitly decide everything based on prompts and tool usage does not capture:

* persistence requirements
* suspend/resume behavior
* duplicate run control
* retry and timeout policy
* lifecycle visibility

This approach hides complexity instead of modeling it.

### 3. Full workflow engine / DAG orchestration

Rejected for v1.

While powerful, this introduces unnecessary complexity before the core execution lifecycle model is stabilized. The immediate need is a correct unified execution model, not distributed orchestration.

## Implications

* All new execution features must integrate through `ExecutionRequest` and `AgentTaskExecutor`.
* No separate execution pipelines should be introduced for automation.
* Persistent behavior must be represented through explicit state models, not prompt context.
* ExecutionPolicy must remain the source of truth for runtime behavior.
* ExecutionLoop must remain generic and unaware of high-level lifecycle decisions.

## Follow-Up Work

* Implement `ExecutionClassifier` with deterministic rules and optional structured LLM assistance.
* Define and implement `RunState` persistence model.
* Introduce `WorkflowDefinition` and `WorkflowRun` storage.
* Implement suspend/resume handling in `ExecutionLoop`.
* Define retry, timeout, and duplicate policies.
* Integrate trigger system with unified execution pipeline.

## Summary

The system will not split into separate runtimes and will not rely on prompt-driven behavior to simulate automation.

Instead, it will use a single execution engine with explicit lifecycle modeling, policy-driven behavior, and persisted run state to support both conversational and automation use cases cleanly.
