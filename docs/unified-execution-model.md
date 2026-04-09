# Unified Execution Model

## Purpose

This document defines the unified execution model for OpenReef.

Its purpose is to ensure that short-lived conversational executions and long-lived persistent automations share the same runtime engine without collapsing their lifecycle semantics into a single ambiguous mode.

The model is designed to preserve a single execution core while making execution lifecycle, persistence behavior, and run-state transitions explicit and inspectable.

## Problem

OpenReef already has a working agent loop, trigger execution, tool routing, and session-based chat behavior. However, the system does not yet have a clean execution lifecycle model that can represent both immediate user requests and persisted resumable runs under one consistent architecture.

Without that lifecycle model, the system trends toward a prompt-driven runtime where automation-like behavior is simulated inside the agent loop instead of being represented explicitly in state and policy.

This becomes a structural problem as soon as the product needs to support:

* long-lived automation
* resumable execution
* trigger-driven continuation
* duplicate run control
* retry and timeout behavior
* inspectable execution outcomes
* standing orders that are more than prompt injection

If these concerns are not modeled directly, they will leak into prompts, loop heuristics, and ad hoc branching logic.

## Design Goals

* Use a single execution engine for all request types.
* Preserve explicit lifecycle distinctions between short-lived and long-lived execution.
* Keep execution behavior policy-driven rather than prompt-driven.
* Support persisted run state for long-lived execution.
* Support suspend and resume semantics for persistent execution.
* Ensure chat, trigger, and resumable execution all flow through the same executor.
* Avoid splitting the system into separate conversational and workflow runtimes.
* Keep the v1 design smaller than a full workflow engine.

## Non-Goals

This design does not aim to:

* build a BPM engine
* support arbitrary DAG execution
* support distributed workflow workers
* support nested workflows in v1
* support full parallel branch execution in v1
* let the LLM implicitly control lifecycle semantics
* replace the existing loop with a separate workflow runtime

## Core Design Principle

The system should have **one execution engine** and **one shared orchestration loop**, but it should not pretend that all execution has the same lifecycle.

The important distinction is not whether a tool is called. The important distinction is whether the execution is:

* short-lived and ephemeral, or
* persisted, resumable, and policy-bound

This design therefore keeps the runtime unified while keeping execution lifecycle explicit.

## Architecture Overview

```text
User Message / Trigger / Event
            │
            ▼
   Execution Intake Layer
            │
            ▼
    ExecutionClassifier
            │
            ├── ephemeral_request
            ├── persistent_request
            ├── resume_request
            └── triggered_request
            │
            ▼
      ExecutionRequest
            │
            ▼
      AgentTaskExecutor
            │
            ▼
       ExecutionLoop
   (single orchestration core)
            │
            ├── think
            ├── decide
            ├── call tool
            ├── emit message
            ├── suspend
            ├── fail
            └── finish
            │
            ▼
      ExecutionResult
            │
            ├── final_response
            ├── persistent_run_created
            ├── run_suspended
            ├── run_resumed
            ├── failed
            └── frozen
```

## Core Concepts

### Execution Intake Layer

The intake layer normalizes raw execution sources into a common input structure before any lifecycle classification is performed.

Representative sources include:

* user chat messages
* standing order firings
* cron triggers
* device or system triggers
* MCP events
* workflow resume signals
* internal system tasks

A normalized intake model keeps the rest of the runtime independent from source-specific parsing.

### ExecutionClassifier

`ExecutionClassifier` is responsible for deciding what lifecycle class an incoming request belongs to.

This decision must not be scattered across the loop or hidden in prompts. It should be made once, up front, using explicit signals such as:

* request source
* recurring intent
* future continuation requirement
* existing run binding
* trigger origin
* persistence requirement

The classifier determines execution mode, but it does not execute the request.

### Execution Modes

Execution modes are lifecycle distinctions, not separate runtimes.

All modes are executed through the same executor and loop.

#### `ephemeral_request`

Immediate short-lived execution.

Characteristics:

* starts from a user request
* may use tools
* does not create a persisted run lifecycle
* does not suspend for later continuation
* usually ends with a direct assistant response

Examples:

* explain a code file
* summarize a document
* draft a reply
* answer a question with or without tool use

#### `persistent_request`

Starts a persisted automation or workflow-backed run.

Characteristics:

* creates durable execution state
* may bind to a trigger or standing order
* may continue later
* may suspend and resume
* requires explicit lifecycle status

Examples:

* every morning summarize the latest issues
* notify me if the price drops
* whenever this event happens, analyze and respond

#### `resume_request`

Continues an existing persisted run.

Characteristics:

* references an existing run
* resumes from explicit stored state
* may be triggered by user reply, approval, external signal, or awaited input

Examples:

* continue the pending run
* approved, continue
* here is my answer, proceed

#### `triggered_request`

Execution initiated by a trigger or external event source.

Characteristics:

* not initiated as a fresh chat request
* may start a new run or continue an existing one
* still executes through the same executor and loop

Examples:

* cron firing
* battery threshold trigger
* MCP event
* scheduled automation invocation

### ExecutionRequest

`ExecutionRequest` is the normalized input model passed into the executor.

Representative shape:

```text
ExecutionRequest
- requestId
- agentId
- sessionId
- mode
- source
- inputPayload
- policy
- runContext?
- workflowContext?
- triggerContext?
- createdAt
```

This model provides the executor with a stable interface regardless of where the request originated.

### ExecutionPolicy

`ExecutionPolicy` determines runtime behavior without forcing the system into separate incompatible execution paths.

Representative fields:

```text
ExecutionPolicy
- allowToolUse
- allowPersistence
- allowSuspend
- maxSteps
- maxToolCalls
- timeoutMs
- duplicatePolicy
- retryPolicy
- failurePolicy
- completionPolicy
```

Key principle:

* execution mode identifies lifecycle class
* execution policy determines allowed runtime behavior

This separation prevents the loop from owning too much hidden policy logic.

### AgentTaskExecutor

`AgentTaskExecutor` is the single execution entry point.

Its responsibilities include:

* validating the incoming request
* applying locking or single-flight constraints
* loading run state when needed
* building execution context
* invoking the shared execution loop
* persisting structured outcomes when required
* publishing the final result to chat, state stores, or runtime observers

The executor is the control point for runtime consistency.

### ExecutionLoop

`ExecutionLoop` is the shared orchestration core for all execution modes.

This loop may:

* emit a direct response
* call tools
* perform structured LLM steps
* persist state
* suspend execution
* fail
* finish

The loop should not own lifecycle semantics by itself.

Lifecycle behavior is constrained by:

* execution mode
* execution policy
* persisted run state
* loaded runtime context

Representative loop actions:

```text
LoopAction
- tool_call
- respond
- structured_llm_step
- persist_state
- suspend_run
- finish
- fail
```

Representative control flow:

```text
INIT
  ↓
PREPARE_CONTEXT
  ↓
PLAN_CURRENT_STEP
  ↓
DECIDE_ACTION
  ├── TOOL_CALL
  ├── EMIT_MESSAGE
  ├── WRITE_RUN_STATE
  ├── SUSPEND
  ├── FAIL
  └── FINISH
          ↓
   SHOULD_CONTINUE?
      ├── yes -> PLAN_CURRENT_STEP
      └── no  -> EXIT
```

### ExecutionResult

`ExecutionResult` is the structured outcome returned by the loop and executor.

Representative outcomes include:

* `final_response`
* `persistent_run_created`
* `run_suspended`
* `run_resumed`
* `failed`
* `frozen`

The result should be inspectable and should not collapse everything into plain assistant text.

### RunState

Persistent execution requires explicit stored run state.

Representative shape:

```text
RunState
- runId
- status
- currentStepIndex
- variables
- lastToolResult?
- waitingReason?
- resumeToken?
- retryCount
- startedAt
- updatedAt
- completedAt?
```

Representative statuses:

```text
RunStatus
- running
- waiting_input
- waiting_event
- waiting_schedule
- retry_scheduled
- completed
- failed
- frozen
- cancelled
```

A persisted run is not just a longer chat turn. It is a state machine with explicit lifecycle transitions.

### WorkflowDefinition

`WorkflowDefinition` is the static reusable description of a deterministic workflow.

Representative contents:

* workflow identity
* version
* trigger binding rules
* step list
* condition rules
* default policy
* metadata

This is the reusable model.

### WorkflowRun

`WorkflowRun` is the live persisted execution instance of a workflow definition.

Representative contents:

* run identity
* workflow identity
* status
* current step index
* bound variables
* execution history
* policy snapshot
* timestamps

This is the live runtime object.

### WorkflowDefinition vs WorkflowRun

This distinction must remain explicit.

* `WorkflowDefinition` is the static reusable description.
* `WorkflowRun` is the live execution instance.

A run should execute against a stable definition snapshot or equivalent versioned representation so that replay, debugging, and reasoning about runtime behavior remain possible even after the workflow definition changes.

## Classification Principles

The system must not classify based on perceived complexity alone.

A complex question may still be ephemeral.
A simple sentence may still require a persistent run.

The correct distinction is whether the request requires persisted lifecycle semantics.

A request should be classified as persistent when one or more of the following are required:

* persisted plan or run state
* future continuation
* explicit wait state
* retry or timeout policy
* duplicate run control
* trigger binding
* resumability
* inspectable lifecycle status

If those requirements are absent, the default should be `ephemeral_request`.

This default matters. It prevents routine chat interactions from being inflated into workflow runs.

## Runtime Flows

### Ephemeral Request Flow

```text
User Message
   ↓
ExecutionClassifier
   ↓ (ephemeral_request)
ExecutionRequest(policy=ephemeral)
   ↓
AgentTaskExecutor
   ↓
ExecutionLoop
   ↓
[tool? maybe]
   ↓
final_response
   ↓
Chat UI
```

In this path, execution is short-lived. It may still use tools and multiple loop steps, but it does not create a durable run lifecycle.

### Persistent Request Flow

```text
User Message
   ↓
ExecutionClassifier
   ↓ (persistent_request)
WorkflowIntentNormalizer
   ↓
WorkflowDefinition / WorkflowRun created
   ↓
ExecutionRequest(policy=persistent)
   ↓
AgentTaskExecutor
   ↓
ExecutionLoop
   ↓
[maybe first step executes]
   ↓
run_state_update
   ↓
WorkflowStore + Chat UI ack
```

In this path, the user message leads to explicit persisted execution state rather than only a transient response.

### Triggered Request Flow

```text
Trigger Fired
   ↓
ExecutionInput(source=trigger)
   ↓
ExecutionClassifier
   ↓ (triggered_request)
ExecutionRequest(policy=triggered)
   ↓
AgentTaskExecutor
   ↓
load existing WorkflowRun / create new run
   ↓
ExecutionLoop
   ↓
suspend / complete / fail
   ↓
persist state
```

In this path, the source is external to the chat UI, but execution still flows through the same executor and loop.

### Resume Request Flow

```text
Resume Signal / User Reply / Awaited Input
   ↓
ExecutionClassifier
   ↓ (resume_request)
ExecutionRequest(policy=resume)
   ↓
AgentTaskExecutor
   ↓
load RunState
   ↓
ExecutionLoop
   ↓
continue from explicit stored state
   ↓
complete / suspend / fail
```

In this path, runtime continuation is based on stored state, not prompt reconstruction.

## Design Rationale

This design intentionally keeps a single execution engine and shared loop while preventing lifecycle semantics from dissolving into prompt-only behavior.

The system should not fork into separate conversational and workflow runtimes because that would create semantic drift in:

* tool behavior
* cancellation behavior
* logging
* locking
* completion handling
* debugging and replay expectations

At the same time, the system should not pretend that ephemeral chat and persistent automation are the same thing. They are not. Their lifecycle semantics differ even if they share the same execution engine.

This design therefore makes the runtime unified at the engine level and explicit at the lifecycle level.

## Rejected Alternatives

### 1. Separate conversational runtime and workflow runtime

Rejected because it would split execution semantics, increase maintenance cost, and create drift between tool behavior, cancellation, logging, persistence, and completion handling.

### 2. Pure agent loop with no explicit lifecycle distinction

Rejected because tool-use decisions alone do not capture persistence, suspend and resume behavior, duplicate control, retry policy, or run-state semantics.

A single loop without explicit lifecycle modeling would only hide the distinction, not remove it.

### 3. Full workflow engine or DAG orchestration

Rejected for v1 because it introduces complexity before the core execution lifecycle model is stabilized.

The immediate requirement is not distributed orchestration or advanced graph execution. The immediate requirement is a correct unified runtime model with explicit persistent run state.

## Implementation Direction

The following components are the minimum architectural building blocks implied by this model:

* `ExecutionClassifier`
* `ExecutionRequest`
* `ExecutionPolicy`
* `AgentTaskExecutor`
* `ExecutionLoop`
* `ExecutionResult`
* `RunState`
* `WorkflowDefinition`
* `WorkflowRun`
* `WorkflowStore`
* `ConditionEvaluator`

Representative module layout:

```text
lib/execution/
  execution_input.dart
  execution_request.dart
  execution_mode.dart
  execution_policy.dart
  execution_result.dart
  execution_classifier.dart
  agent_task_executor.dart
  execution_loop.dart
  execution_loop_models.dart

lib/workflows/
  workflow_definition.dart
  workflow_run.dart
  workflow_step.dart
  workflow_store.dart
  workflow_runner_support.dart
  condition_evaluator.dart
  workflow_compiler.dart

lib/triggers/
  trigger_models.dart
  trigger_system.dart
  trigger_dispatcher.dart

lib/runtime/
  run_state.dart
  execution_lock_manager.dart
  execution_history_store.dart
  retry_scheduler.dart
```

This layout is illustrative, not mandatory. The important thing is preserving the separation between:

* general execution runtime
* workflow persistence and orchestration concerns
* trigger sources
* operational runtime state

## Invariants

The following invariants should remain true as implementation evolves:

* There is one executor.
* There is one shared execution loop.
* Execution modes represent lifecycle distinctions, not different engines.
* Persistent execution must have explicit stored run state.
* Suspend and resume behavior must be represented in state, not inferred from prompts.
* Policy must constrain runtime behavior explicitly.
* WorkflowDefinition and WorkflowRun must remain separate concepts.
* Triggered execution must use the same runtime core as user-initiated execution.

## Open Questions

The architecture direction is clear, but several implementation decisions still need to be settled:

* How much of execution classification should be rule-based versus LLM-assisted with structured output?
* What is the exact persistence backend for `RunState` and workflow storage?
* What versioning strategy should be used for `WorkflowDefinition` snapshots?
* How should retries be scheduled and observed?
* What duplicate policy defaults should apply to standing orders and trigger-driven runs?
* Which suspend reasons are required in v1 versus later phases?
* How should chat-facing acknowledgements differ from run-state updates for persistent requests?

## Summary

OpenReef should not solve automation by creating a second runtime, and it should not solve it by hiding lifecycle semantics inside prompt-driven loop behavior.

The correct direction is:

* one execution engine
* one shared execution loop
* explicit lifecycle classification
* policy-driven behavior
* persisted run state for long-lived execution

That gives the system a clean path from chat execution to real automation without collapsing both into the same ambiguous model.

Assumed Existing Runtime Guarantees
-----------------------------------

This execution model is **not** written for a greenfield runtime.

It assumes that OpenReef already has a functioning execution backbone and that the unified execution model will be layered on top of that backbone rather than replacing it.

The following runtime guarantees are assumed to already exist and remain authoritative unless explicitly superseded by a later architecture decision:

*   a single production execution entry path already exists
    
*   the active executor path already owns real request execution
    
*   the active loop already supports multi-step tool use
    
*   tool routing already exists and remains the only production tool dispatch path
    
*   result delivery already has an existing runtime-to-UI propagation path
    
*   persistence for sessions, chat state, or runtime state already exists in production form
    
*   loop safety protections already exist for failure/freeze/termination handling
    
*   confirmation and approval handling already exist as runtime policy mechanisms
    
*   trigger execution already enters the production runtime rather than a fake/demo path
    

This document therefore does **not** define a replacement runtime.

It defines a clearer lifecycle model for the runtime that already exists.

The purpose of this model is to make persistent and resumable execution semantics explicit without discarding the current executor, loop, routing, persistence, and delivery guarantees already present in the system.

What This Model Changes
-----------------------

This model adds lifecycle clarity and persistent execution semantics on top of the existing runtime.

Specifically, it introduces the following changes:

### 1\. Explicit lifecycle classification

Incoming work is classified up front into explicit execution lifecycle classes rather than allowing lifecycle semantics to emerge implicitly inside prompts or ad hoc loop logic.

This adds:

*   ephemeral\_request
    
*   persistent\_request
    
*   resume\_request
    
*   triggered\_request
    

The purpose is not to create separate runtimes.

The purpose is to make execution lifecycle visible, inspectable, and enforceable.

### 2\. Explicit persistent run semantics

Long-lived execution is no longer treated as “just another chat turn.”

Persistent automation and resumable execution gain first-class runtime semantics such as:

*   run creation
    
*   explicit run status
    
*   suspend and resume behavior
    
*   duplicate handling
    
*   retry and timeout handling
    
*   inspectable lifecycle outcomes
    

### 3\. Explicit separation between reusable workflow description and live run state

This model formalizes the distinction between:

*   WorkflowDefinition
    
*   WorkflowRun
    

This prevents the system from representing persistent automation only through prompt instructions or reconstructed chat history.

### 4\. Up-front lifecycle-aware execution policy application

This model makes execution policy a first-class runtime input rather than allowing policy to remain scattered across the loop, triggers, and prompt-level logic.

This enables:

*   duplicate run control
    
*   suspend permissions
    
*   persistence permissions
    
*   timeout behavior
    
*   retry behavior
    
*   completion behavior
    

### 5\. Resume and continuation as runtime state, not prompt reconstruction

This model introduces explicit runtime continuation semantics.

Continuation should happen through stored run state and lifecycle-aware execution requests, not by asking the model to “remember what it was doing” from chat history alone.

### 6\. Trigger-origin execution as a first-class lifecycle source

Triggers and external events are explicitly modeled as execution sources within the same runtime contract.

This avoids the current class of architectural drift where trigger-driven behavior becomes a side system instead of a first-class execution path.

What This Model Does Not Replace
--------------------------------

This model is an execution-lifecycle extension, not a runtime rewrite.

It does **not** replace the following existing production primitives:

### 1\. Existing executor ownership

The current production executor remains the single runtime owner for execution entry, coordination, and result handling.

This model does not introduce a second executor.

### 2\. Existing shared loop ownership

The current production orchestration loop remains the shared loop used for execution.

This model does not replace that loop with a separate workflow engine or second reasoning runtime.

### 3\. Existing tool router

The current production tool router remains the only valid tool dispatch layer.

This model does not create a separate workflow-only tool execution system.

### 4\. Existing persistence backbone

Current production persistence for sessions, messages, run-related state, or other durable runtime records remains authoritative unless explicitly migrated.

This model adds lifecycle semantics on top of that persistence foundation.

### 5\. Existing result propagation path

The current result-delivery path from runtime to visible user-facing surfaces remains in force.

This model does not introduce a separate response-delivery stack for workflow or trigger execution.

### 6\. Existing loop safety mechanisms

Current protections for bounded execution, freeze/fail semantics, compaction safety, or confirmation behavior remain valid.

This model does not reopen or weaken those guarantees.

### 7\. Existing trigger-to-runtime execution path

Current real trigger execution wiring remains the production path.

This model only makes lifecycle classification and persistent execution semantics more explicit within that path.

### 8\. Existing approval and confirmation controls

Current approval/confirmation enforcement remains the active safety boundary for sensitive execution.

This model does not move lifecycle semantics into a way that bypasses or dilutes those controls.

Codebase Mapping
----------------

The following mapping is intended to anchor this model to the current codebase so that implementation does not drift into clean-room redesign.

This section is illustrative at the contract level and should be refined as implementation proceeds.

### Existing production concepts -> role in unified execution model

#### Current executor entry point -> AgentTaskExecutor

The existing execution entry point remains the single executor.

In this model, that executor becomes the lifecycle-aware entry point for:

*   ephemeral execution
    
*   persistent execution
    
*   resumed execution
    
*   triggered execution
    

The main architectural change is not replacement, but expansion of responsibility around lifecycle classification and persistent run loading.

#### Current shared agent loop -> ExecutionLoop

The current loop maps directly to the shared orchestration core in this model.

It remains the runtime component responsible for iterative execution actions such as:

*   deciding next action
    
*   calling tools
    
*   emitting responses
    
*   continuing or stopping
    

If a naming split is introduced later, it should be treated as an architectural clarification, not a second runtime.

#### Current request/session input path -> ExecutionInput / ExecutionRequest

Current user message, trigger task, system task, or resume signal intake should be normalized into a stable execution request model.

This is a normalization layer added in front of the executor.

It should not create a second request-processing path.

#### Current session/run persistence -> RunState / WorkflowRun

Where the current codebase already persists execution-related state, that persistence should be extended to represent lifecycle-aware run state for persistent executions.

The important requirement is not introducing persistence from scratch.

The requirement is ensuring that persistent lifecycle state is represented explicitly and inspectably.

#### Current workflow-like automation definitions -> WorkflowDefinition

Any persisted reusable automation definition, standing-order-backed template, or trigger-driven reusable task definition should map conceptually to WorkflowDefinition.

If such structures already exist under different names, they should be treated as candidates for normalization rather than duplication.

#### Current visible execution outcome models -> ExecutionResult

Any current runtime result object such as session result, loop result, or completion result should map into the unified ExecutionResult concept.

The goal is to make lifecycle outcomes explicit, not to erase existing result types prematurely.

#### Current trigger execution path -> triggered\_request

Any current production trigger path should normalize into the same execution-request contract and pass through the same executor.

The trigger system should remain a source of execution, not an alternative runtime.

#### Current approval / mailbox / confirmation path -> policy-constrained execution boundary

Current approval and confirmation primitives remain enforcement boundaries during execution.

They should be treated as runtime policy constraints that continue to apply regardless of execution mode.

### Expected implementation style

Implementation should prefer:

*   extending existing classes where semantics already match
    
*   introducing small lifecycle-aware wrappers where needed
    
*   adding normalization and classification layers ahead of the executor
    
*   avoiding parallel runtime abstractions that duplicate current executor or loop logic
    

Implementation should avoid:

*   replacing the current executor with a second lifecycle executor
    
*   creating a second loop for workflows
    
*   introducing workflow-only tool routing
    
*   re-implementing persistence in parallel with existing durable stores
    
*   splitting result delivery into separate conversational and automation channels unless the product explicitly requires different projections on top of the same underlying result contract
    

Relationship to Existing Gaps and Runtime Work
----------------------------------------------

This execution model should be interpreted as an architectural continuation of existing runtime work, not as a reset of prior decisions.

### It does not reopen closed consolidation work

This model does not reopen any closed work related to:

*   runtime-path consolidation
    
*   loop safety and termination correctness
    
*   approval flow correctness
    
*   trigger-to-runtime execution wiring
    
*   storage and security baseline
    
*   previously closed architectural unifications
    

Where those guarantees already exist, this model assumes them and builds on them.

### It does not replace active runtime safety work

This model does not supersede current protections in the production loop or executor.

Instead, it provides a clearer lifecycle contract within which that safety work continues to operate.

### It is the architectural answer to persistent-execution gaps

This model is specifically intended to support resolution of open gaps related to:

*   workflow layer absence
    
*   weak persistent automation semantics
    
*   trigger-driven continuation
    
*   resumable execution
    
*   explicit run-state modeling
    
*   duplicate control for long-lived execution
    
*   standing orders that need runtime representation rather than prompt injection
    

### It depends on existing production truth

This model only works if implementation remains anchored to the current production runtime path.

Any implementation that treats this document as permission to create a second executor, second orchestration loop, or separate workflow runtime would be a regression.

### It should be used as a refinement document

This document should be used to:

*   refine execution lifecycle semantics
    
*   formalize persistent execution behavior
    
*   guide code-level extension of the current executor and loop
    
*   make runtime state transitions explicit and inspectable
    

It should **not** be used to justify broad replacement of already-working production runtime components.