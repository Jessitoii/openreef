# OpenReef

## What OpenReef Is

OpenReef is a mobile-first AI agent system with a policy-governed runtime and a canonical architecture contract.

It is designed around a deterministic execution path:
`ExecutionRequest → Executor → AgentLoop → ToolRouter → ExecutionResult`.

The project uses explicit lifecycle modes, bounded loop behavior, structured tool outcomes, trigger arbitration, and disciplined memory writes.

OpenReef is inspired by systems such as OpenClaw in spirit (agentic execution + tool use + automation), but it is not a clone. Its architecture is intentionally stricter on lifecycle legality, policy enforcement, and ownership boundaries.

## Why It Exists

Many agent systems fail in predictable ways when they scale from demos to real workflows:

- runtime behavior is encoded in prompts instead of explicit state machines
- tool execution paths bypass policy checks
- automation and chat paths diverge into separate runtime behaviors
- memory writes are uncontrolled and accumulate low-quality state
- “workflow” behavior lacks durable lifecycle semantics

OpenReef exists to address these problems with explicit contracts:

- one execution engine
- one shared loop
- policy-enforced execution boundaries
- deterministic transition rules
- clear separation of architecture domains

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

The following examples reflect architecture intent and current maturity, not blanket production claims:

1. **Scheduled automation run**
   - a schedule trigger fires
   - scheduler normalizes event and applies missed-fire/drift handling
   - trigger lifecycle arbitration chooses queue/coalesce/replace behavior
   - executor runs a `triggered_request`

2. **Multi-step tool usage**
   - loop plans actions
   - tool calls are validated and policy-checked in router
   - confirmation is required for sensitive actions
   - normalized `ToolResult` statuses feed continuation logic

3. **Persistent memory usage**
   - context pipeline retrieves bounded memory candidates
   - loop executes with compiled context
   - post-turn memory writes apply reliability discipline

4. **Trigger-based execution with foreground conflict**
   - active chat and trigger run conflict is resolved via policy/arbitration
   - decision is explicit (queue/reject/replace/coalesce), not implicit prompt behavior

5. **Skill-driven behavior**
   - enabled skills are evaluated for relevance
   - skill context injection is budgeted and policy-bound
   - permissions remain enforced at router time

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
