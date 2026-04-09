# Architecture Decisions Backlog

These items are unresolved architectural choices that require explicit decisions before full lock-in.

## Decision candidates
1. Run/workflow persistence schema and versioning strategy.
   - Why decision: multiple viable storage/schema approaches; no finalized contract yet.
2. Execution classifier strategy split (rules-only vs structured assist).
   - Why decision: affects determinism, cost, and implementation complexity.
3. Final default policy constants by source class (duplicate/queue/retry/timeout/priority).
   - Why decision: values are policy tuning choices, not mere implementation gaps.
