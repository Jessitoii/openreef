# Memory Write Discipline

## Purpose
Define reliability criteria for post-turn memory persistence.

## Core Data Models
`MemoryWriteCandidate`: candidate id, fact, importance, source turn, reliability flags, disposition.

## Rules
Long-term writes require:
- successful turn completion
- no unresolved critical tool failure affecting reliability
- importance threshold met
- duplicate suppression pass

Ambiguous candidates:
- short-term only or dropped

Error-heavy/failed turns:
- no long-term writes

## Observability
Record accepted/rejected candidates and reasons.
