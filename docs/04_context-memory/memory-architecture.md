# Memory Architecture

## Purpose
Define memory store taxonomy, ownership boundaries, retrieval merge strategy, and degradation behavior.

## Store Taxonomy
- **Session short-term store**: recent interaction state for active session continuity.
- **Long-term semantic store**: durable facts/episodes approved by write discipline.
- **Pointer/index store**: lightweight routing metadata for fast candidate lookup.
- **Run audit references**: links to tool outcomes and transition logs used for provenance.

## Ownership Rules
- `lib/memory/` owns retrieval and persistence behavior.
- `lib/context/` consumes retrieval outputs; it does not own memory durability decisions.
- Pointer/index updates are owned by memory services, not UI or loop logic.

## Pointer/Index Boundaries
- Pointer/index is discovery metadata, not authoritative fact content.
- Pointer/index entries may reference semantic records but cannot replace them.
- Pointer/index failures degrade candidate discovery only; they must not corrupt semantic store.

## Retrieval Merge Strategy
1. Retrieve candidates from long-term semantic store.
2. Retrieve relevant short-term/session items.
3. Merge and de-duplicate by stable semantic key.
4. Apply recency + relevance + reliability ranking.
5. Return bounded set for context assembly.

## Fallback/Degradation Behavior
- Semantic store unavailable: use short-term + pointer/index fallback and annotate degraded mode.
- Pointer/index unavailable: use direct semantic queries with latency warning marker.
- Full memory subsystem unavailable: continue with history-only context and explicit audit marker.

## Constraints
- Memory writes remain governed by [Memory Write Discipline](./memory-write-discipline.md).
- Retrieval failures must be explicit in observability traces.

## Related Documents
- [Context Assembly](./context-assembly.md)
- [Memory Write Discipline](./memory-write-discipline.md)
