# Execution Policy

## Purpose
Define operational policy semantics for duplicate handling, queueing, retries, timeouts, suspend/resume legality, and completion visibility.

## Scope
In scope:
- policy schema and defaults
- source-type default semantics
- legality rules and enforcement boundaries
- observability for enforcement branches

Out of scope:
- UI-specific policy presentation
- product-level preference workflows

## Responsibilities
- Executor enforces policy legality at runtime.
- Trigger arbitration aligns pre-dispatch decisions to policy.
- Loop consumes limits (`maxSteps`, `maxToolCalls`, timeout) but cannot redefine policy.

## Core Concepts
- **Policy is executable contract**: not guidance text.
- **Explicit branch recording**: every policy decision path is logged.
- **Safety over convenience**: sensitive or illegal requests fail/freeze instead of silently degrading.

## Core Data Models
`ExecutionPolicy` fields:
- `allowToolUse`, `allowPersistence`, `allowSuspend`
- `maxSteps`, `maxToolCalls`, `timeoutMs`
- `duplicatePolicy`: `allow|reject|replace_running|coalesce|queue`
- `queuePolicy`: `fifo|priority|none_reject`
- `retryPolicy`: `none|fixed(maxRetries, backoffMs)`
- `failurePolicy`: `fail_run|freeze_run`
- `completionPolicy`: `emit_chat_response|state_only|both`

## Default Semantics by Source
| Source type | Mode default | Duplicate | Queue | Retry | Timeout profile | Completion |
|---|---|---|---|---|---|---|
| `chat_user` | `ephemeral_request` | reject | none_reject | none | interactive/short | emit_chat_response |
| `trigger.schedule` / `trigger.interval` | `triggered_request` | queue | fifo | fixed | background/medium | both |
| `trigger.mcp_event` (bursty) | `triggered_request` | coalesce | fifo | fixed | background/short-medium | both |
| `resume_signal` | `resume_request` | reject | priority | none | inherited | both |
| manual system action | `persistent_request` | queue | priority | fixed | medium-long | both |

## Suspend/Resume Legality Grid
| Condition | Suspend | Resume | Notes |
|---|---|---|---|
| `allowSuspend=false` | illegal | illegal | suspend request must fail/freeze |
| ephemeral mode | illegal | illegal | no durable run |
| persistent mode, waiting status | legal | legal | requires persisted `RunState` |
| triggered mode without durable run | illegal | illegal | must first create persistent run |
| terminal status | illegal | illegal | terminal states are non-resumable |

## Execution Flow
1. Executor binds policy snapshot to request.
2. Admission checks enforce duplicate/queue rules.
3. Runtime enforces loop/tool limits.
4. Suspend/resume legality evaluated on every related action.
5. Completion visibility applied to session projection.

## Failure Modes
- policy snapshot missing required fields → reject request.
- duplicate policy conflict with no legal branch → reject with explicit reason.
- queue saturation with `none_reject` path → reject and record.
- retry overrun beyond max retries → terminal fail/freeze.

## Constraints
- Numeric defaults must be configurable and versioned.
- Policy overrides must be traceable to source (trigger, workflow, user config).
- Policy branches must never be implicit.

## Invariants
- each request has one effective policy snapshot.
- duplicate, queue, and retry branches are mutually consistent.
- completion visibility branch is deterministic.

## Observability
Log per request:
- policy hash/version
- selected duplicate branch
- queue admission or rejection reason
- retry count and backoff application
- completion visibility branch

## Related Documents
- [Execution Model](./execution-model.md)
- [Trigger Lifecycle](../06_triggers-automation/trigger-lifecycle.md)
- [Session Lifecycle](../03_agent/session-lifecycle.md)

## Open Questions
- final numeric defaults (timeouts, retry counts, queue bounds)
- priority ordering when multiple trigger classes contend
