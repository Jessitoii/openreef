# Skills Overview

## Purpose
Define skill registry boundary, relevance activation path, and bounded injection contract.

## Scope
This file is the boundary summary for skills runtime behavior.
Detailed lifecycle, permission, and creator mechanics live in linked canonical files.

## Responsibilities
- Maintain canonical installed/enabled skill registry.
- Produce per-turn activation decisions with explicit reasons.
- Inject only relevant skill context within budget and policy.
- Preserve implemented-vs-target maturity labeling.

## Core Data Models
- `SkillDefinition`
- `SkillRuntimeState`
- `SkillActivationDecision`

## Implemented vs Target
- Implemented: baseline registry and UI surfaces; runtime integration remains partial.
- Target: deterministic relevance-based auto-injection with strict manifest/sandbox constraints.

## Open Questions
- Final relevance scoring strategy (rules-only vs hybrid scorer).
- Final trust policy defaults for community skills.

## Related Documents
- [Skill Lifecycle](./skill-lifecycle.md)
- [Skill Permissions and Sandbox](./skill-permissions-and-sandbox.md)
- [Skill-Creator](./skill-creator.md)
