# OpenReef
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat&logo=flutter&logoColor=white)
![Android](https://img.shields.io/badge/Android-native-3DDC84?style=flat&logo=android&logoColor=white)
![Gemma](https://img.shields.io/badge/Gemma-on--device-4285F4?style=flat&logo=google&logoColor=white)
![Offline](https://img.shields.io/badge/Offline-100%25-success?style=flat)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat)
![Status](https://img.shields.io/badge/Status-In_Development-orange?style=flat)

> Privacy-first, fully offline personal AI agent for Android.  
> Runs entirely on-device — no cloud, no telemetry, no data leaving the device.  
> Built on Flutter, LiteRT-LM inference, native Android tools, MCP integrations, and persistent local memory.

---

## What It Does

OpenReef is not a chat wrapper. It is an agent runtime designed around **predictable, inspectable, enforceable execution**.

Instead of encoding behavior in prompts and hoping the model interprets them correctly, OpenReef enforces a deterministic execution path:

```
ExecutionRequest → Executor → AgentLoop → ToolRouter → ExecutionResult
```

Every step has an explicit contract:

- Lifecycle modes are validated, not inferred
- Continuation is bounded and policy-controlled
- Tool execution is normalized and never bypasses enforcement layers
- Outcomes are structured, not parsed from free text

Chat, automation triggers, scheduled tasks, and skills all run through the same engine under the same rules. There is no divergence between "agent mode" and "automation mode".

---

## Why

Most agent systems fail outside demos. The pattern is consistent:

- Behavior encoded in prompts instead of explicit state machines
- Tool calls that bypass validation layers
- Separate runtimes for chat vs automation
- Memory that accumulates without structure or reliability filters
- Workflows that exist as prompt conventions instead of real execution models

The result: systems that cannot be debugged, resumed, or scaled reliably.

OpenReef exists to eliminate these failure modes. The goal is not more capable agents. The goal is **operationally reliable** agents.

---

## Core Capabilities

- Multi-step agent loop with bounded continuation control
- Unified tool execution through a single validated router
- Trigger-driven automation routed through the same executor as interactive sessions
- Context assembly with explicit memory retrieval and reduction pipeline
- Memory write discipline — low-confidence data is not persisted
- Skill registry with lifecycle, permission, and activation boundaries
- Execution policy covering deduplication, queuing, retries, suspend/resume, and completion visibility
- Fully offline — all inference runs on-device via LiteRT-LM
- Voice pipeline: wake word → STT → agent → TTS (partial)

---

## Architecture

```
┌─────────────────────────────────────────┐
│           ExecutionRequest              │
│  (chat / trigger / schedule / manual)   │
└────────────────────┬────────────────────┘
                     │
            ┌────────▼────────┐
            │    Executor     │  validates legality, loads/creates run state,
            │                 │  owns lifecycle transitions
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │   Agent Loop    │  bounded step planning/acting,
            │                 │  requests tool actions
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │   Tool Router   │  schema validation, permission checks,
            │                 │  confirmation policy, normalized outcomes
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │ ExecutionResult │  structured terminal outcome,
            │                 │  session-visible state
            └─────────────────┘
```

Domain responsibilities are explicitly separated:

| Domain | Responsibility |
|---|---|
| Execution model | Normalized input, mode classification, policy binding |
| Executor | Legality validation, run state, lifecycle transitions |
| Agent loop | Bounded step planning, action requests |
| Tool router | Schema validation, permissions, confirmation, result normalization |
| Result projection | Structured terminal outcomes |
| Trigger lifecycle | Arbitration, scheduler semantics |
| Context & memory | Compilation pipeline, write discipline |
| Skills | Lifecycle, sandboxing, permission boundaries |

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter |
| On-device inference | `flutter_gemma` / LiteRT-LM |
| Local storage | SQLite, sqlite-vec |
| Voice (wake word) | Porcupine |
| Voice (STT) | Whisper Tiny |
| Integrations | MCP (Model Context Protocol) |
| Platform | Android |

---

## Getting Started

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

> Environment setup and configuration are documented in [`docs/`](./docs/README.md). If your environment is not fully configured, start with [Status and Scope](./docs/00_meta/status-and-scope.md).

---

## Repository Structure

```
openreef/
├── docs/               # Canonical architecture, policy, lifecycle, and backlog docs
├── lib/
│   ├── agent/          # Agent loop, session lifecycle, mailbox
│   ├── tools/          # Tool router, result contracts, confirmation policy
│   ├── memory/         # Memory architecture and write discipline
│   ├── context/        # Context assembly and compilation
│   ├── skills/         # Skills lifecycle and permission sandboxing
│   ├── mcp/            # MCP integration layer
│   └── ui/             # Application UI
├── android/            # Platform integration and native bridge surfaces
├── ios/                # iOS platform assets
├── assets/             # Application assets
└── test/               # Runtime component test coverage
```

> `lib/agent/` is the agent runtime. `lib/tools/` is the tool runtime. There are no top-level `agents/` or `tools/` directories.

---

## Documentation

Canonical documentation lives under `docs/`. The [Documentation Map](./docs/00_meta/doc-map.md) is the authoritative ownership index.

### Meta
- [Docs Root](./docs/README.md)
- [Documentation Map](./docs/00_meta/doc-map.md)
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

### Backlog
- [Architecture Decisions](./docs/90_decisions/README.md)
- [Implementation Gaps](./docs/99_gaps/README.md)

---

## Current Status

### Implemented
- Unified execution architecture contracts (model / policy / loop / router / result flow)
- Trigger lifecycle arbitration contract and scheduler semantics
- Context assembly pipeline and memory write discipline
- Skills lifecycle and sandbox/permission boundary definitions
- Canonical documentation ownership map

### Partial
- Skills auto-injection runtime path
- Trigger arbitration coverage across all runtime scenarios
- Voice pipeline end-to-end readiness (wake → STT → agent → TTS)
- Context compiler rollout depth

### Unresolved
- Final persistence backend and schema/versioning for run/workflow state
- Numeric defaults for queue bounds, retry counts, timeouts, and priority tuning
- Classifier strategy: rules-only vs. hybrid

---

## Roadmap

Near-term work is driven by open decisions and known gaps.

1. Finalize persistence schema and versioning for run/workflow lifecycle state
2. Lock numeric execution policy defaults per source class
3. Complete trigger arbitration implementation coverage
4. Complete skills auto-injection runtime path with strict policy boundaries
5. Advance voice pipeline to verified end-to-end readiness

Full backlog: [Architecture Decisions](./docs/90_decisions/README.md) · [Implementation Gaps](./docs/99_gaps/README.md)

---

## Contributing

Before proposing architectural or behavioral changes:

1. Read the [Documentation Map](./docs/00_meta/doc-map.md)
2. Identify the authoritative file for your target concept
3. Update the canonical doc when any contract or behavior changes
4. Route unresolved decisions to `docs/90_decisions/` and implementation deltas to `docs/99_gaps/`

Contributions that bypass ownership boundaries or reintroduce prompt-driven architecture drift will not be accepted.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
