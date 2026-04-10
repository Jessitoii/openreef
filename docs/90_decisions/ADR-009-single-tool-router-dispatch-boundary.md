# ADR-009: Single Tool Router Dispatch Boundary

## Status
Accepted

## Context
Multiple tool invocation paths increase policy bypass risk and create inconsistent error handling.

## Decision
Enforce one tool dispatch boundary through `ToolRouter` for native, MCP, and skill-exposed tools.

## Rationale
A single dispatch surface centralizes validation, permission checks, confirmation routing, and normalization.

## Consequences
- Direct adapter execution outside router is invalid.
- Router is the mandatory pre-dispatch policy checkpoint.

## Alternatives Considered
- Domain-specific independent tool executors.

## Related Documents
- [Tool Router](../05_tools/tool-router.md)
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)
