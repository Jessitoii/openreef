# Tool Result Contract

## Purpose
Define normalized tool outcome schema and status semantics consumed by loop, session projection, and persistence.

## Scope
In scope:
- required result fields
- status categories and mapping rules
- context injection and persistence boundaries

Out of scope:
- adapter internals

## Responsibilities
- provide uniform success/failure shape regardless of adapter source.
- preserve policy and rejection reasons as structured fields.
- keep outcome payloads auditable and bounded.

## Core Concepts
- all tool outcomes are explicit status enums.
- policy/approval outcomes cannot be hidden in prose.
- payload references can be externalized, but status metadata stays inline.

## Core Data Models
### ToolResult
Required:
- `callId`
- `toolId`
- `status`
- `durationMs`
- `observabilityRef`

Optional:
- `outputPayload`
- `errorCode`
- `errorMessage`
- `policyReason`

### Status Set
- `success`
- `rejected`
- `validation_error`
- `execution_error`
- `timeout`
- `unavailable`
- `blocked_by_policy`

## Status Mapping Rules
| Source branch | ToolResult status |
|---|---|
| successful adapter execution | `success` |
| explicit approval rejection/expiry | `rejected` |
| schema validation failure | `validation_error` |
| adapter exception | `execution_error` |
| execution exceeds timeout | `timeout` |
| tool missing/unavailable | `unavailable` |
| policy permission block | `blocked_by_policy` |

## Context Injection Rules
Inject into loop context:
- `toolId`
- normalized `status`
- bounded output summary for success
- reason codes for non-success statuses

## Persistence Rules
Persist with run/session records:
- call metadata (`requestId/runId/callId/toolId` correlation)
- terminal status and reason fields
- pointer/reference to full payload/audit artifact

## Failure Modes
- malformed result object from adapter layer → convert to `execution_error` with normalization failure code.
- missing required fields after normalization → fail normalization and emit structured contract violation.

## Constraints
- normalized status is mandatory.
- reason-bearing statuses require reason fields.
- status values are closed set unless explicitly versioned.

## Invariants
- one terminal result per call.
- status semantics are stable across adapters.

## Observability
- status histogram by tool and adapter type
- top error/rejection/policy reason codes
- payload truncation/externalization counts

## Related Documents
- [Tool Router](./tool-router.md)
- [Execution Model](../02_system/execution-model.md)

## Open Questions
- standard payload truncation thresholds for high-volume outputs.
