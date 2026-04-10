# Permissions Model

## Purpose
Define global permission enforcement primitives across execution, tools, triggers, skills, and native integrations.

## Scope
In scope:
- permission decision model
- enforcement boundaries
- audit requirements

Out of scope:
- low-level platform permission APIs

## Responsibilities
- establish consistent permission decisions before capability execution.
- compose global policy with tool/skill/native-specific checks.
- guarantee auditable denial/allow outcomes.

## Core Concepts
- permission checks are pre-dispatch control points.
- decisions are explicit (`allow|deny|require_confirmation`).
- deny paths are first-class outcomes, not exceptions.

## Core Data Models
### PermissionDecision
- `decisionId`
- `subject` (agent/sub-agent/skill)
- `resource` (tool/capability/data scope)
- `action`
- `decision` (`allow|deny|require_confirmation`)
- `reasonCode`
- `policyRefs[]`
- `timestamp`

### PermissionContext
- `requestId`, `runId?`, `callId?`, `trustLevel?`, `sourceType`, `sessionId?`

## Enforcement Flow
1. Build permission context.
2. Resolve applicable policies (global + domain-specific).
3. Evaluate allow/deny/confirmation decision.
4. Enforce branch before dispatch.
5. Record decision and correlation metadata.

## Failure Modes
- missing policy references → fail closed (deny) with config error marker.
- conflicting policy outcomes → choose strictest and log conflict.
- unavailable permission service component → fail closed for sensitive actions.

## Constraints
- permission model cannot be bypassed by prompt instructions.
- approval-required operations must route through confirmation policy/flow.
- denied actions must remain visible in structured outcomes.

## Invariants
- each sensitive action has one permission decision record.
- decision record includes reason code and policy references.

## Observability
- allow/deny/confirmation rates by subject/resource/action
- conflict resolution counts
- fail-closed counts due to dependency failures

## Related Documents
- [Confirmation and Side-Effect Policy](../05_tools/confirmation-and-side-effect-policy.md)
- [Tool Router](../05_tools/tool-router.md)
- [Skill Permissions and Sandbox](../07_skills/skill-permissions-and-sandbox.md)

## Open Questions
- canonical subject/resource taxonomy for cross-platform permission reporting.
