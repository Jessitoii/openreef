# Skill Lifecycle

## Purpose
Define administrative and runtime state transitions for skills from discovery through activation.

## Scope
In scope:
- install/enable/disable lifecycle
- per-turn activation transitions
- legality constraints and failure outcomes

Out of scope:
- permission semantics (see permissions/sandbox doc)

## Responsibilities
- maintain deterministic skill administrative state.
- enforce activation legality by install/enable status.
- surface activation outcomes and reasons.

## Core Concepts
- install state and enable state are separate controls.
- activation is per-turn/runtime decision, not permanent state.
- disabled or uninstalled skills are non-activatable.

## Core Data Models
### SkillRuntimeState
- `skillId`
- `installState` (`installed|uninstalled`)
- `enableState` (`enabled|disabled`)
- `trustLevel`
- `healthStatus`
- `lastUsedAt?`

### SkillActivationDecision
- `skillId`
- `decisionStatus` (`activated|skipped_budget|skipped_policy|skipped_irrelevant`)
- `activationReason`
- `injectionBudget`
- `toolAllowanceSnapshot`

## State Transitions
Administrative:
`discovered → installed → enabled → disabled → enabled`

Runtime:
`enabled → activated_per_turn → idle`

Uninstall:
`installed|disabled → uninstalled`

Illegal:
- `uninstalled → activated_per_turn`
- `disabled → activated_per_turn` (without explicit override contract)

## Execution Flow
1. Registry loads skill metadata.
2. Admin state checks filter install/enable eligibility.
3. Runtime relevance evaluates candidates.
4. Activation decision emitted with reason and budget.
5. Activated skills contribute bounded context and permitted actions.

## Failure Modes
- invalid lifecycle transition request → reject with reason.
- stale registry entry → mark health degraded and skip activation.
- activation budget exhaustion → `skipped_budget`.

## Constraints
- lifecycle transitions are explicit and auditable.
- runtime activation cannot mutate admin install state.

## Invariants
- one activation decision per enabled skill per turn.
- activation decisions are immutable after finalization for a turn.

## Observability
- install/enable/disable event counts
- activation decision distribution
- health degradation reasons

## Related Documents
- [Skills Overview](./skills-overview.md)
- [Skill Permissions and Sandbox](./skill-permissions-and-sandbox.md)

## Open Questions
- explicit override contract for emergency-only disabled-skill activation.
