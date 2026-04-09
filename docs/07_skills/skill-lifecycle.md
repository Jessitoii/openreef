# Skill Lifecycle

## Purpose
Define install/enable/disable/activation transitions.

## State Transitions
`discovered → installed → enabled → activated_per_turn → idle`

Administrative transitions:
- `enabled → disabled`
- `installed → uninstalled`

Illegal transitions:
- `uninstalled → activated_per_turn`
- `disabled → activated_per_turn` (without explicit override contract)

## Observability
Track install, enable/disable, activation decision, and health-state changes.
