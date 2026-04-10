# ADR-007: Agent Loop Hardening and Deterministic Terminal States

## Status
Accepted

## Context
Unbounded loops, repeated no-progress cycles, and compaction failures can cause non-deterministic behavior and poor recovery.

## Decision
Keep loop execution bounded with blocked-progress detection, explicit terminal intents, and deterministic failure/freeze behavior.

## Rationale
Guard rails prevent infinite/no-progress execution and make terminal outcomes inspectable for UI, retry, and operations.

## Consequences
- Loop must emit structured terminal requests.
- Compaction failure paths require safe fallback or explicit terminal failure.
- Telemetry must include blocked-progress and terminal reason data.

## Alternatives Considered
- Best-effort unbounded loop with ad hoc break conditions.

## Related Documents
- [Agent Loop](../03_agent/agent-loop.md)
- [Compaction Strategy](../04_context-memory/compaction-strategy.md)
