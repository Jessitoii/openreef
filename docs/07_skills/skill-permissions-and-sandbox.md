# Skill Permissions and Sandbox

## Purpose
Define enforcement of skill permission manifests, trust levels, and runtime sandbox boundaries.

## Scope
In scope:
- permission manifest structure
- trust-level policy
- sandbox enforcement boundaries

Out of scope:
- skill lifecycle transitions

## Responsibilities
- validate permission manifests at install/enable time.
- enforce declared permissions at runtime dispatch.
- prevent privilege escalation across skill/global boundaries.

## Core Concepts
- manifest is declarative capability boundary.
- trust level influences default enforcement strictness.
- skill state must remain namespaced.

## Core Data Models
### PermissionManifest (runtime subset)
- `skillId`
- `requestedToolScopes[]`
- `requiresConfirmationOverrides?`
- `dataAccessScopes[]`
- `networkAccessPolicy`

### SkillTrustLevel
- `built_in`
- `verified`
- `community`
- `local`

### SandboxDecision
- `skillId`
- `action`
- `decision` (`allow|block|require_confirmation`)
- `reasonCode`

## Enforcement Flow
1. Validate manifest schema.
2. Resolve effective trust-level policy.
3. For each runtime action, evaluate manifest + global policy.
4. Emit sandbox decision.
5. Route blocked/confirmation paths through tool policy boundary.

## Failure Modes
- malformed manifest → install/enable reject.
- requested scope exceeds policy → block and record reason.
- namespace violation attempt → block and raise security audit event.

## Constraints
- skill permissions cannot exceed global tool/runtime permissions.
- sandbox policy cannot be bypassed by prompt instructions.
- skill-owned state namespace is mandatory (`skill:{skillId}:*`).

## Invariants
- every skill action has one sandbox decision.
- trust-level policy is explicitly versioned in enforcement traces.

## Observability
- blocked vs allowed action counts by trust level
- confirmation-required counts per skill
- namespace violation attempts

## Related Documents
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)
- [Skill Lifecycle](./skill-lifecycle.md)

## Open Questions
- default policy profile differences between `community` and `local` trust levels.
