# ADR-004: Vector-Semantic Memory Retrieval

## Status
Accepted

## Context
Keyword-only retrieval is insufficient for robust context recall and leads to low-relevance memory surfaces.

## Decision
Adopt semantic memory retrieval with ranked candidate merging from long-term and session stores, supported by index metadata.

## Rationale
Semantic retrieval improves recall quality and enables relevance/recency/reliability ranking for bounded context assembly.

## Consequences
- Memory retrieval requires ranking traces and dedupe semantics.
- Pointer/index metadata is supportive and non-authoritative.

## Alternatives Considered
- Keyword-only retrieval strategy.

## Related Documents
- [Memory Architecture](../04_context-memory/memory-architecture.md)
- [Context Assembly](../04_context-memory/context-assembly.md)
