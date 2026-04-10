# Standing Orders

## Purpose
Define standing orders as structured runtime directives applied during trigger handling and context assembly.

## Scope
In scope:
- rule structure and matching semantics
- action directives and priority handling
- application trace requirements

Out of scope:
- freeform prompt text directives

## Responsibilities
- represent persistent behavioral directives as machine-evaluable rules.
- apply matching rules during trigger lifecycle.
- expose applied/skipped rule traces.

## Core Concepts
- standing orders are data objects, not prose fragments.
- rule evaluation is deterministic for same inputs.
- rule side effects are bounded by policy and routing constraints.

## Core Data Models
### StandingOrderRule
- `ruleId`
- `enabled`
- `matchPredicate`
- `actionDirective`
- `priority`
- `applicableTriggerTypes`

### StandingOrderEvaluation
- `ruleId`
- `eventId`
- `matched`
- `appliedDirective?`
- `reason`
- `evaluatedAt`

## State Transitions
`defined → enabled|disabled → evaluated → matched_applied|matched_skipped|not_matched`

## Execution Flow
1. Load enabled rules for trigger type.
2. Evaluate predicates against normalized `TriggerEvent`.
3. Resolve priority and conflict ordering.
4. Attach resulting directives to trigger request context.
5. Record evaluation outcomes.

## Failure Modes
- invalid predicate expression → disable rule and record validation failure.
- conflicting directives at same priority → deterministic tie-break and record conflict reason.
- directive requires unsupported capability → skip directive and mark reason.

## Constraints
- standing orders cannot bypass execution policy or confirmation boundaries.
- freeform text-only standing order definitions are non-authoritative.

## Invariants
- each evaluated rule yields one evaluation record.
- applied directive chain is ordered and deterministic.

## Observability
- rule match rates
- applied/skipped counts by reason
- conflict and tie-break counts

## Related Documents
- [Trigger Lifecycle](./trigger-lifecycle.md)
- [Context Assembly](../04_context-memory/context-assembly.md)

## Open Questions
- final tie-break ordering when multiple directives have equal priority and overlapping scope.
