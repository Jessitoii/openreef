# Mailbox and Approval Flow

## Purpose
Define the transport and lifecycle for sub-agent approval escalation requests.

## Scope
This file owns escalation mechanics only.
Global confirmation policy classes and approval requirements are authoritative in [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md).

## Mailbox Lifecycle
`created → queued_for_coordinator → pending_resolution → resolved_approved|resolved_rejected|expired`

## Execution Flow
1. Sub-agent emits escalation request with correlation identifiers.
2. Coordinator enqueues request into mailbox channel.
3. Request enters pending resolution state.
4. Coordinator resolves approved/rejected/expired.
5. Resolution is returned to router for normalized `ToolResult` mapping.

## Transport Contract
Mailbox request minimum fields:
- `mailboxRequestId`
- `originRunId`
- `originCallId`
- `toolId`
- `approvalClass`
- `createdAt`

Mailbox decision minimum fields:
- `mailboxRequestId`
- `decision` (`approved|rejected|expired`)
- `resolvedAt`
- `resolvedBy`

## Constraints
- Mailbox cannot redefine confirmation policy classes.
- Mailbox decisions must be immutable once terminal.

## Related Documents
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)
- [Tool Result Contract](../05_tools/tool-result-contract.md)
