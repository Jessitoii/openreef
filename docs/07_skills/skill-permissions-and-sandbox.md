# Skill Permissions and Sandbox

## Purpose
Define manifest-based permission enforcement and sandbox constraints.

## Responsibilities
- Enforce declared skill permission manifest at tool dispatch time.
- Apply trust-level controls (`built_in|verified|community|local`).
- Block privilege escalation attempts.

## Constraints
- Skill permissions cannot exceed global tool/runtime policy.
- Skill state must be namespaced (`skill:{skillId}:*`) and auditable.

## Open Questions
- Final default trust policy for community skills.
