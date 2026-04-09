# Compaction Strategy

## Purpose
Define compaction levels, invocation conditions, and failure-safe behavior.

## Core Data Models
`CompactionResult`: `level(micro|auto|full)`, `status(applied|skipped|failed_fallback_applied)`, `tokenDelta`.

## State Transitions
`not_needed → micro|auto|full → applied`

Failure path: `auto|full → failed_fallback_applied`.

## Constraints
- Compaction retries must be bounded.
- If fallback cannot keep required sections within budget, execution fails explicitly.

## Observability
Record compaction level, delta, failure/fallback branch, and resulting section budgets.
