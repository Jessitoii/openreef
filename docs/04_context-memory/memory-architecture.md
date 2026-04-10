# Memory Architecture

## Purpose
Define memory store taxonomy, ownership boundaries, retrieval merge strategy, index roles, and degraded behavior.

## Scope
In scope:
- logical memory stores
- retrieval and merge pipeline
- pointer/index boundaries
- failure/degradation handling

Out of scope:
- storage engine implementation details

## Responsibilities
- provide high-quality candidates for context assembly.
- preserve durable memory with provenance references.
- isolate lightweight index navigation from semantic payload ownership.

## Core Concepts
- semantic store and index are complementary, not interchangeable.
- retrieval is multi-source merge + ranking.
- degraded operation remains explicit and auditable.

## Store Taxonomy
- **Short-term/session store**: recent interaction continuity for active sessions.
- **Long-term semantic store**: durable facts/episodes accepted by write discipline.
- **Pointer/index store**: lightweight keys, anchors, and recency metadata.
- **Run/audit reference store**: links to tool/run artifacts used for provenance.

## Core Data Models
### MemoryRecord
- `memoryId`, `type`, `contentRef`, `importance`, `reliability`, `createdAt`, `updatedAt`

### MemoryPointer
- `pointerId`, `memoryId`, `indexKey`, `scoreHints`, `lastAccessedAt`

### RetrievalQuery
- `queryId`, `sourceRequestId`, `filters`, `limit`, `mode`, `timestamp`

### RetrievalResult
- `queryId`, `candidateRefs`, `rankingTrace`, `degradedMode?`

## Retrieval Merge Strategy
1. Retrieve long-term semantic candidates.
2. Retrieve short-term/session candidates.
3. Retrieve pointer/index expansions.
4. Merge and de-duplicate on stable semantic key.
5. Rank by relevance, recency, and reliability.
6. Return bounded candidate list with ranking trace.

## Fallback/Degradation Behavior
- semantic store unavailable → use short-term + pointer/index path, set degraded flag.
- pointer/index unavailable → direct semantic retrieval with latency marker.
- full memory subsystem unavailable → history-only fallback with explicit degraded mode.

## Constraints
- memory ownership remains in `lib/memory/`; context layer consumes outputs only.
- pointer/index cannot become authoritative fact storage.
- every returned candidate must be traceable to source record.

## Invariants
- index references cannot orphan durable records.
- merge stage cannot emit duplicate semantic keys.
- degraded mode must always be annotated.

## Observability
- retrieval source counts
- merge dedupe counts
- ranking decisions and ties
- degradation branch and reason

## Related Documents
- [Context Assembly](./context-assembly.md)
- [Memory Write Discipline](./memory-write-discipline.md)

## Open Questions
- final weighting formula among relevance/recency/reliability in ranking.
