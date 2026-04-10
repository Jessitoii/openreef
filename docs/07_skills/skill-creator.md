# Skill-Creator

## Purpose
Define the relationship between Skill-Creator functionality and runtime governance boundaries.

## Scope
In scope:
- artifact-generation boundary
- handoff into lifecycle/manifest validation
- non-bypass rules

Out of scope:
- generic runtime activation rules

## Responsibilities
- support generation/update of skill artifacts.
- hand generated artifacts into normal install/validation lifecycle.
- preserve auditability of generated skill changes.

## Core Concepts
- Skill-Creator is a producer, not a privileged installer.
- generated skills follow same manifest/sandbox constraints as all skills.
- creation success does not imply activation success.

## Core Data Models
### SkillCreatorOutput
- `skillDraftId`
- `artifactRefs`
- `manifestDraft`
- `generationTrace`
- `createdAt`

### SkillInstallValidationResult
- `skillDraftId`
- `schemaValid`
- `manifestValid`
- `policyValid`
- `errors[]`

## Execution Flow
1. Skill-Creator produces candidate artifacts.
2. Validation pipeline checks schema/manifest/policy.
3. Valid artifacts enter normal install lifecycle.
4. Enable/activation occurs only through standard lifecycle transitions.

## Failure Modes
- malformed generated artifacts → validation failure.
- policy-incompatible manifest → blocked installation.
- missing required metadata → rejected until corrected.

## Constraints
- Skill-Creator cannot auto-enable skills without lifecycle transition.
- Skill-Creator cannot bypass permission/sandbox enforcement.

## Invariants
- generated skill changes are traceable to creator run/request.
- install decision remains external to generation step.

## Observability
- generation attempts and success rates
- validation failure categories
- install acceptance/rejection after generation

## Related Documents
- [Skill Lifecycle](./skill-lifecycle.md)
- [Skill Permissions and Sandbox](./skill-permissions-and-sandbox.md)

## Open Questions
- review gate requirements for community-distributed Skill-Creator outputs.
