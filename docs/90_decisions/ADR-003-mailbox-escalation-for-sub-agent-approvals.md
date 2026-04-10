# ADR-003: Mailbox Escalation for Sub-Agent Approvals

## Status
Accepted

## Context
Sub-agent tool calls that require confirmation need deterministic handling without bypassing approval policy.

## Decision
Use mailbox escalation transport for sub-agent approval requests; keep confirmation policy authority centralized in tool policy docs.

## Rationale
Separating policy from transport keeps approval requirements consistent while preserving deterministic pending/timeout/reject handling for delegated actions.

## Consequences
- Sub-agent confirmation paths must route through mailbox lifecycle.
- Mailbox decisions are terminal and auditable.
- Global confirmation classes remain centrally defined.

## Alternatives Considered
- Allow sub-agents to invoke direct approval UI bypassing mailbox transport.

## Related Documents
- [Mailbox and Approval Flow](../03_agent/mailbox-and-approval-flow.md)
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)
