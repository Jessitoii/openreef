# ADR-011: Standing Orders as Structured Runtime Rules

## Status
Accepted

## Context
Representing standing orders as prompt text alone is non-deterministic and hard to audit.

## Decision
Represent standing orders as structured runtime rule objects with explicit predicates, directives, and priorities.

## Rationale
Structured rules enable deterministic evaluation, conflict handling, and traceability during trigger processing and context assembly.

## Consequences
- Rule evaluation results must be recorded.
- Freeform text-only directives are non-authoritative.

## Alternatives Considered
- Unstructured prompt appends for behavioral directives.

## Related Documents
- [Standing Orders](../06_triggers-automation/standing-orders.md)
- [Trigger Lifecycle](../06_triggers-automation/trigger-lifecycle.md)
