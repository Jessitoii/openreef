# Mailbox and Approval Flow

## Purpose
Define sub-agent escalation transport and lifecycle for approval resolution.

## Scope
This file owns escalation mechanics only.
Global confirmation policy classes and side-effect sensitivity rules are authoritative in [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md).

## Responsibilities
- accept escalation requests from sub-agent tool actions.
- queue and track coordinator-facing approval items.
- return immutable approval decisions to router/executor.

## Core Concepts
- mailbox is a transport/state machine, not policy authoring.
- decisions are explicit and terminal (`approved|rejected|expired`).
- each mailbox request correlates to one origin tool call.

## Core Data Models
### MailboxRequest
Required fields:
- `mailboxRequestId`
- `originRunId`
- `originCallId`
- `toolId`
- `approvalClass`
- `payloadRef`
- `createdAt`

### MailboxDecision
Required fields:
- `mailboxRequestId`
- `decision` (`approved|rejected|expired`)
- `resolvedAt`
- `resolvedBy`
- `reasonCode?`

## State Transitions
`created → queued_for_coordinator → pending_resolution → resolved_approved|resolved_rejected|expired`

Illegal transitions:
- any resolved state → pending states
- decision mutation after terminal resolution

## Execution Flow
1. Sub-agent emits escalation request with correlation ids.
2. Coordinator queue admission validates request shape.
3. Request enters pending resolution state.
4. Coordinator resolves decision.
5. Router maps decision to normalized `ToolResult` status.

## Failure Modes
- malformed request payload → reject before queue admission.
- coordinator unavailable → keep queued with retry policy marker.
- timeout without resolution → mark `expired` and emit terminal decision.

## Constraints
- mailbox cannot redefine confirmation policy.
- mailbox request/decision ids are immutable.
- terminal decisions are append-only audit records.

## Invariants
- one mailbox request maps to one origin call.
- one terminal decision per mailbox request.

## Observability
- queue admission timestamp and latency
- pending duration
- terminal decision and resolver identity
- correlation to request/run/call ids

## Related Documents
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)
- [Tool Result Contract](../05_tools/tool-result-contract.md)

## Open Questions
- coordinator retry/backoff behavior under prolonged offline conditions.
