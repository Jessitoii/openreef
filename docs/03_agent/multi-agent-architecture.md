# Multi-Agent Architecture

## Purpose
Define role separation between main agent and sub-agents while preserving one engine and one shared loop contract.

## Scope
In scope:
- role boundaries
- delegation contract
- policy inheritance
- escalation responsibilities

Out of scope:
- distributed worker infrastructure
- alternative runtime engines

## Responsibilities
- Main agent owns user-facing outcome and session projection.
- Sub-agents execute delegated scoped tasks under inherited policy boundaries.
- Executor remains single lifecycle authority across agent roles.

## Core Concepts
- multi-agent in OpenReef is role orchestration, not runtime duplication.
- sub-agents cannot bypass router/confirmation/policy boundaries.
- delegated scope must be explicit and bounded.

## Core Data Models
### DelegationEnvelope
Required fields:
- `delegationId`
- `parentRequestId`
- `parentRunId`
- `subAgentId`
- `taskScope`
- `policySnapshot`
- `createdAt`

### DelegationOutcome
Required fields:
- `delegationId`
- `status` (`completed|failed|cancelled|expired`)
- `summary`
- `toolOutcomeRefs`
- `completedAt`

## State Transitions
`delegated → accepted → running → completed|failed|cancelled|expired`

Illegal transitions:
- terminal delegation state → running
- delegation without policy snapshot

## Execution Flow
1. Main agent creates delegation envelope.
2. Sub-agent accepts scoped task.
3. Sub-agent runs via shared loop and router.
4. Sensitive calls escalate through mailbox path.
5. Delegation outcome returns to main agent.

## Failure Modes
- invalid task scope → delegation rejected.
- policy mismatch/inheritance failure → fail delegation before execution.
- unresolved escalation timeout → delegation fails/expires.

## Constraints
- no sub-agent-specific bypass path for tools.
- sub-agent policy can be stricter than parent, never looser.

## Invariants
- every sub-agent action traceable to parent request/run.
- delegation does not create a second lifecycle model.

## Observability
- delegation creation/accept timestamps
- policy snapshot hash
- escalation count and outcomes
- delegation terminal status/reason

## Related Documents
- [Execution Model](../02_system/execution-model.md)
- [Mailbox and Approval Flow](./mailbox-and-approval-flow.md)
- [Tool Router](../05_tools/tool-router.md)

## Open Questions
- final concurrency caps for simultaneous sub-agent delegations on constrained devices.
