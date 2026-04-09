# Status and Scope

## Implemented reality

- Single executor and shared loop direction is adopted.
- Runtime contracts for execution, loop, tools, triggers, context/memory, and skills are defined.
- Skill and voice runtime integration remain partial.

## Target architecture

- Full trigger arbitration matrix coverage.
- Full context compiler rollout with auditable reductions and compaction fallback behavior.
- Deterministic skill auto-injection with strict permission/sandbox enforcement.
- Complete voice wake→STT→agent→TTS runtime path routed through unified intake.

## Unresolved areas

- Persistence backend/schema/versioning for run and workflow snapshots.
- Final default tuning for duplicate/queue/retry/timeout policies by source class.
- Final classifier strategy split (rules-only vs structured assist).
