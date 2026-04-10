# ADR-012: AutoDream Must Not Be Authoritative for Core Correctness

## Status
Accepted

## Context
AutoDream maturity is partial/non-operational; treating it as required for correctness would create fragile dependencies.

## Decision
Keep AutoDream optional and non-authoritative for baseline memory correctness until full production readiness is established.

## Rationale
Core memory behavior must remain correct without deferred background consolidation workers.

## Consequences
- Primary memory writes/retrieval cannot depend on AutoDream jobs.
- AutoDream remains explicitly maturity-gated in documentation and runtime claims.

## Alternatives Considered
- Requiring AutoDream to maintain baseline memory consistency.

## Related Documents
- [AutoDream](../04_context-memory/autodream.md)
- [Memory Write Discipline](../04_context-memory/memory-write-discipline.md)
- [Implementation Gaps](../99_gaps/README.md)
