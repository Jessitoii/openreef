# ADR-008: MCP Secret Boundary and Endpoint Trust

## Status
Accepted

## Context
Persisting credential-bearing endpoint data in general connection records introduces local secret exposure risk and weak trust boundaries.

## Decision
Store MCP secrets only in secure secret storage, keep endpoint descriptors sanitized, and apply explicit trust validation for reconnect behavior.

## Rationale
Separating endpoint identity from secret material reduces leak risk while preserving reconnect functionality under controlled trust rules.

## Consequences
- Endpoint records must not contain plaintext secrets.
- Reconnect behavior is stricter for legacy/migrated endpoints.
- Trust validation is required before auto-reconnect.

## Alternatives Considered
- Persist full credential-bearing endpoint URLs in connection records.

## Related Documents
- [Trust Boundaries](../10_security/trust-boundaries.md)
- [Permissions Model](../10_security/permissions-model.md)
- [Gap Tracker](../gap_tracker.md)
