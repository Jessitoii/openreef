# OpenReef

## What OpenReef Is

OpenReef is an agent runtime built to execute real actions under explicit control, not prompt interpretation.

Instead of relying on loosely guided LLM behavior, OpenReef enforces a deterministic execution path:

ExecutionRequest → Executor → AgentLoop → ToolRouter → ExecutionResult

Every step in this path has a defined contract:

*   lifecycle modes are explicit and validated
    
*   continuation is bounded and policy-controlled
    
*   tool execution is normalized and never bypasses enforcement layers
    
*   outcomes are structured, not inferred from text
    

The system is designed so that automation, chat, triggers, and skills all run through the same engine, under the same rules. There is no parallel “agent mode” vs “automation mode” drift.

OpenReef is inspired by agentic systems like OpenClaw, but takes a stricter approach:

*   no prompt-driven lifecycle semantics
    
*   no hidden execution paths
    
*   no implicit state transitions
    

The goal is not to make agents more flexible.The goal is to make them **predictable, inspectable, and enforceable**.

## Why It Exists

Most agent systems break the moment they move beyond demos.

The failure pattern is consistent:

*   behavior is encoded in prompts instead of explicit state machines
    
*   tool calls bypass enforcement layers or rely on best-effort validation
    
*   automation logic diverges from chat logic into separate runtimes
    
*   memory accumulates without reliability or structure
    
*   “workflows” exist as prompt conventions instead of real execution models
    

This creates systems that:

*   cannot be debugged reliably
    
*   cannot be resumed safely
    
*   cannot enforce policy consistently
    
*   cannot scale beyond simple use cases
    

OpenReef exists to eliminate these failure modes.

It enforces:

*   a single execution engine across all entry points (chat, triggers, manual runs)
    
*   a single bounded agent loop with explicit continuation rules
    
*   a policy layer that defines what is allowed, not the prompt
    
*   deterministic lifecycle transitions instead of implicit behavior
    
*   disciplined memory and context handling instead of uncontrolled accumulation
    

This is not about making agents more “intelligent”.

It is about making them **operationally reliable**.

## Core Capabilities

- Multi-step agent loop execution with bounded control.
- Unified tool execution through a single router.
- Trigger-driven automation routed into the same executor.
- Context assembly and memory retrieval with explicit reduction flow.
- Memory write discipline for long-term persistence quality.
- Skill registry, lifecycle, permission, and activation boundaries.
- Execution policy layer for duplicates, queueing, retries, suspend/resume legality, and completion visibility.
- Mobile/client-side orientation with native bridge boundaries and truthful maturity labeling.

## Architecture (High-Level)

OpenReef keeps runtime responsibilities separated so behavior is inspectable and enforceable:

1. **Execution model** receives normalized input, classifies mode, and binds policy.
2. **Executor** validates legality, loads/creates run state, and owns state transitions.
3. **Agent loop** performs bounded step planning/acting and requests actions.
4. **Tool router** validates schemas, applies permission/confirmation policy, and normalizes tool outcomes.
5. **Result projection** returns structured terminal outcomes and session-visible state.

Domain separation is explicit:

- execution model and run semantics
- execution policy defaults and legality
- loop behavior and bounded continuation
- tools and confirmation boundaries
- trigger lifecycle and scheduler behavior
- context compilation and memory architecture
- skills lifecycle and permission sandboxing

## Documentation

Canonical documentation lives under `docs/`.

### Start Here

- [Docs Root](./docs/README.md)
- [Documentation Map (authoritative ownership)](./docs/00_meta/doc-map.md)
- [Architecture Principles](./docs/00_meta/architecture-principles.md)
- [Status and Scope](./docs/00_meta/status-and-scope.md)

### System Runtime

- [System Overview](./docs/02_system/system-overview.md)
- [Execution Model](./docs/02_system/execution-model.md)
- [Execution Policy](./docs/02_system/execution-policy.md)

### Agent Runtime

- [Agent Loop](./docs/03_agent/agent-loop.md)
- [Session Lifecycle](./docs/03_agent/session-lifecycle.md)
- [Mailbox and Approval Flow](./docs/03_agent/mailbox-and-approval-flow.md)

### Tools and Automation

- [Tool Router](./docs/05_tools/tool-router.md)
- [Tool Result Contract](./docs/05_tools/tool-result-contract.md)
- [Confirmation and Side-Effect Policy](./docs/05_tools/confirmation-and-side-effect-policy.md)
- [Trigger Lifecycle](./docs/06_triggers-automation/trigger-lifecycle.md)
- [Trigger Scheduler](./docs/06_triggers-automation/trigger-scheduler.md)
- [Standing Orders](./docs/06_triggers-automation/standing-orders.md)

### Context, Memory, Skills

- [Context Assembly](./docs/04_context-memory/context-assembly.md)
- [Memory Architecture](./docs/04_context-memory/memory-architecture.md)
- [Memory Write Discipline](./docs/04_context-memory/memory-write-discipline.md)
- [Skills Overview](./docs/07_skills/skills-overview.md)
- [Skill Lifecycle](./docs/07_skills/skill-lifecycle.md)
- [Skill Permissions and Sandbox](./docs/07_skills/skill-permissions-and-sandbox.md)

### Platform and Security

- [Voice Overview](./docs/08_voice-mobile/voice-overview.md)
- [Wake Word](./docs/08_voice-mobile/wake-word.md)
- [Mobile Native Integration](./docs/08_voice-mobile/mobile-native-integration.md)
- [Model Runtime](./docs/09_models/model-runtime.md)
- [Permissions Model](./docs/10_security/permissions-model.md)
- [Trust Boundaries](./docs/10_security/trust-boundaries.md)

### Delivery, Decisions, and Gaps

- [Migration Plan](./docs/12_delivery/migration-plan.md)
- [Architecture Decisions Backlog](./docs/90_decisions/README.md)
- [Implementation Gaps Backlog](./docs/99_gaps/README.md)

## Current Status

Status is tracked in canonical docs and split into implemented vs partial vs unresolved.

### Implemented

- Canonical docs ownership map and architecture principles.
- Unified execution architecture contracts (model/policy/loop/router/result flow).
- Trigger lifecycle arbitration contract and scheduler semantics.
- Context assembly pipeline and memory write discipline rules.
- Skills lifecycle and sandbox/permission boundary definitions.

### Partial

- Skills runtime integration completeness (automatic injection path).
- Trigger arbitration coverage across all runtime scenarios.
- Voice runtime end-to-end maturity (wake/STT/agent/TTS chain not GA).
- Context compiler rollout depth and tuning in runtime implementation.

### Not Implemented / Unresolved

- Final persistence backend/schema/versioning decisions for run/workflow state.
- Final numeric defaults for queue bounds, retry counts, timeout durations, and priority tuning.
- Final classifier strategy decision (rules-only vs hybrid assist).

## Example Capabilities

The following scenarios illustrate how OpenReef behaves in real execution paths.

### 1\. Scheduled Reminder with Policy Enforcement

A user sets:

> “Remind me every morning to drink water.”

*   a schedule trigger is registered
    
*   the scheduler fires at the correct time, applying drift and missed-fire handling
    
*   the event is normalized into an ExecutionRequest
    
*   trigger arbitration decides whether to run, queue, or coalesce
    
*   the executor starts a controlled run under policy
    
*   the agent loop produces a reminder without bypassing lifecycle rules
    

There is no special “reminder mode” — this is the same execution path as any other run.

### 2\. Multi-Step Tool Execution with Confirmation

A user asks:

> “Book a ride and notify me when it arrives.”

*   the agent loop plans multiple steps
    
*   each tool call is routed through the ToolRouter
    
*   schema validation and permission checks are enforced
    
*   sensitive actions trigger confirmation requirements
    
*   tool outcomes are returned as structured ToolResult objects
    
*   loop continuation depends on normalized results, not raw text
    

No step can skip validation or policy enforcement.

### 3\. Persistent Memory with Controlled Writes

A user interacts repeatedly with the system.

*   context assembly retrieves only relevant, bounded memory
    
*   the agent operates on a compiled context, not full history
    
*   after execution, memory writes are filtered by reliability rules
    
*   low-confidence or noisy data is not persisted
    

Memory is treated as a **managed resource**, not a dumping ground.

### 4\. Trigger vs Active Session Conflict Resolution

A background trigger fires while the user is actively interacting.

*   both flows are routed through the same execution system
    
*   arbitration logic determines the outcome:
    
    *   queue
        
    *   reject
        
    *   replace
        
    *   coalesce
        
*   the decision is explicit and policy-driven
    

There is no undefined behavior or race condition hidden in prompts.

### 5\. Skill-Guided Execution Under Constraints

A skill is enabled for a specific task domain.

*   the system evaluates whether the skill is relevant
    
*   skill context is injected within strict limits
    
*   permissions and tool access remain enforced at runtime
    
*   the skill influences behavior but cannot override policy
    

Skills extend capability without breaking execution guarantees.

## Getting Started

OpenReef is an evolving engineering project.

Current baseline commands used by the project docs are:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

If your environment is not fully configured yet, start with the canonical docs and implementation backlog:

- [Docs Root](./docs/README.md)
- [Status and Scope](./docs/00_meta/status-and-scope.md)
- [Implementation Gaps](./docs/99_gaps/README.md)

## Repository Structure

Primary directories:

- `docs/` — canonical architecture, policy, lifecycle, and backlog documents.
- `lib/` — runtime implementation domains (`agent`, `tools`, `memory`, `context`, `skills`, `mcp`, `ui`).
- `android/` — platform integration and native boundary surfaces.
- `test/` — test coverage for runtime components.
- `ios/` and `assets/` — platform and application assets.

Notes:

- There is no top-level `agents/` directory; agent runtime code lives in `lib/agent/`.
- There is no top-level `tools/` directory; tool runtime code lives in `lib/tools/`.

## Roadmap (Short)

Near-term work is driven by open decisions and known gaps, not speculative features.

1. Finalize persistence schema/versioning for run/workflow lifecycle state.
2. Lock numeric execution policy defaults per source class.
3. Complete trigger arbitration implementation coverage.
4. Complete skills auto-injection runtime path with strict policy boundaries.
5. Advance voice pipeline from partial to verified end-to-end readiness.

Roadmap sources:

- [Architecture Decisions Backlog](./docs/90_decisions/README.md)
- [Implementation Gaps Backlog](./docs/99_gaps/README.md)

## Contributing

OpenReef is actively evolving; contributions should align with canonical docs.

Before proposing architectural or behavioral changes:

1. Read [Documentation Map](./docs/00_meta/doc-map.md).
2. Confirm the authoritative file for your target concept.
3. Update the canonical doc when behavior/contract changes.
4. Route unresolved choices to `docs/90_decisions/` and implementation deltas to `docs/99_gaps/`.

Contributions that bypass ownership boundaries or reintroduce prompt-driven architecture drift are likely to be rejected.

## License

License metadata should be confirmed from the repository’s formal licensing file/policy.
Until then, treat this section as a placeholder.
