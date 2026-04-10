# Implementation Gaps Backlog

These are known partial-coverage areas with accepted direction but incomplete implementation.

## Known gaps
1. Trigger arbitration matrix coverage is partial.
   - Why gap: policy contract exists; runtime coverage across all scenarios is incomplete.
2. Skill runtime automatic injection path is partial.
   - Why gap: architecture defined; activation/injection completeness not fully wired.
3. Voice wake→STT→agent→TTS GA readiness is incomplete.
   - Why gap: target pipeline defined; end-to-end production validation pending.
4. Full context compiler rollout milestones remain in-progress.
   - Why gap: compiler contract exists; staged migration from heuristic assembly still incomplete.

5. Scheduler health and drift observability coverage is incomplete.
   - Why gap: scheduler contract is defined, but runtime instrumentation coverage is not complete.
6. Session projection conflict-resolution handling needs full runtime coverage.
   - Why gap: projection rules are documented, but stale-event ordering handling is not fully implemented.
