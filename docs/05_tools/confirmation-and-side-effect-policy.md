# Confirmation and Side-Effect Policy

## Purpose
Define global policy authority for side-effect sensitivity classes and confirmation requirements.

## Scope
In scope:
- sensitivity classes
- confirmation classes
- caller-specific approval requirements (main agent vs sub-agent)

Out of scope:
- mailbox transport mechanics

## Responsibilities
- classify tools by side-effect risk.
- map sensitivity to confirmation requirements.
- enforce non-bypassable approval policy boundaries.

## Core Concepts
- policy authority lives here, not in mailbox transport docs.
- runtime policy may tighten requirements; it must not silently loosen high-risk classes.
- approval outcomes map to structured tool statuses.

## Core Data Models
### SideEffectClass
- `A_read_only`
- `B_local_mutation`
- `C_external_or_irreversible`

### ConfirmationClass
- `none_required`
- `user_required`
- `mailbox_required`
- `policy_blocked`

### ApprovalRequirementRule
- `toolId`
- `sideEffectClass`
- `defaultConfirmationClass`
- `allowedCallerTypes`
- `overridePolicyRef?`

## Policy Matrix (Caller × Sensitivity)
| Caller | Class A | Class B | Class C |
|---|---|---|---|
| Main agent | allow by policy | user approval per policy | explicit user approval required |
| Sub-agent | allow by policy | mailbox approval required | mailbox + explicit user resolution required |

## Execution Flow
1. Router resolves tool side-effect class.
2. Runtime computes effective confirmation class (manifest + policy override).
3. Approval branch executes (`none`, direct user, mailbox, blocked).
4. Outcome maps to normalized `ToolResult`.

## Failure Modes
- tool missing classification → treat as blocked until classified.
- override policy conflict → choose stricter rule and log conflict.
- approval timeout → `rejected` or `blocked_by_policy` per rule.

## Constraints
- this file is sole authority for confirmation classes and mapping rules.
- policy cannot downgrade Class C below explicit approval requirement.
- prompt instructions cannot bypass confirmation policy.

## Invariants
- every tool invocation has an effective side-effect class.
- every approval-required path has explicit terminal decision.

## Observability
- approval-required invocation rate by class
- rejection and timeout rates
- policy override conflict counts

## Related Documents
- [Tool Router](./tool-router.md)
- [Mailbox and Approval Flow](../03_agent/mailbox-and-approval-flow.md)
- [Tool Result Contract](./tool-result-contract.md)

## Open Questions
- final mapping granularity for device-critical actions across OEM-specific capabilities.
