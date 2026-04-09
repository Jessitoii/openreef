# Permissions Model

## Purpose
Define global permission enforcement principles across tools, triggers, skills, and native bridges.

## Placeholder Status
This file is intentionally scoped to global principles.
Detailed confirmation classes and tool-level policy are authoritative in [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md).

## Global Enforcement Principles
- Permission checks occur before dispatch.
- Confirmation-required actions must resolve through approved confirmation path.
- Policy blocks must produce structured non-success outcomes.
- Permission decisions must be auditable and correlated to request/run/call identifiers.

## Related Documents
- [Tool Router](../05_tools/tool-router.md)
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)
- [Trust Boundaries](./trust-boundaries.md)
