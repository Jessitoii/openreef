# Confirmation and Side-Effect Policy

## Purpose
Define the global policy authority for confirmation classes, side-effect sensitivity classes, and approval requirements.

## Side-Effect Sensitivity Classes
- **Class A (read-only)**: no external side effects; confirmation usually not required.
- **Class B (local mutable)**: modifies local state/resources; confirmation may be required by user policy.
- **Class C (external irreversible or sensitive)**: external write/send/delete/financial/device-critical actions; confirmation required.

## Confirmation Classes
- `none_required`
- `user_required`
- `mailbox_required` (sub-agent escalation path)
- `policy_blocked`

## Approval Rules
- Tool manifests map each tool to sensitivity and default confirmation class.
- Runtime policy may tighten confirmation requirements but cannot relax Class C below explicit approval.
- Sub-agent Class B/C calls require mailbox-mediated approval resolution.
- Rejected/expired approvals return normalized non-success `ToolResult` statuses.

## Main vs Sub-Agent Policy
| Caller | Class A | Class B | Class C |
|---|---|---|---|
| Main agent | allow by policy | user approval per policy | explicit user approval required |
| Sub-agent | allow by policy | mailbox approval required | mailbox approval + explicit user resolution |

## Constraints
- This file is the sole policy authority for confirmation requirements.
- Prompt text cannot bypass confirmation classes.
- Policy blocks and approval outcomes must remain structured and auditable.

## Related Documents
- [Tool Router](./tool-router.md)
- [Tool Result Contract](./tool-result-contract.md)
- [Mailbox and Approval Flow](../03_agent/mailbox-and-approval-flow.md)
