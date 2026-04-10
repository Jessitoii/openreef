# ADR-002: Single Runtime Path via Dart LiteRtBridge

## Status
Accepted

## Context
The codebase historically carried mixed assumptions about multiple inference/runtime bridges.

## Decision
Use a single production runtime path through Dart-side `LiteRtBridge`/model adapter wiring.

## Rationale
A single reachable path avoids split behavior and ownership ambiguity while keeping runtime debugging and policy enforcement tractable.

## Consequences
- No secondary production runtime path is treated as authoritative.
- Runtime integration and failure handling are concentrated in one path.

## Alternatives Considered
- Maintain parallel runtime paths for fallback.

## Related Documents
- [Execution Model](../02_system/execution-model.md)
- [System Overview](../02_system/system-overview.md)
- [Current Status](../current-status.md)
