# Multi-Agent Architecture

## Purpose
Define role boundaries between main agent and sub-agents.

## Scope
OpenReef uses one runtime engine and one shared loop; multi-agent behavior is role separation, not a second engine.

## Responsibilities
- Main agent owns user-facing session result.
- Sub-agents perform delegated tasks under inherited policy constraints.
- Sub-agents cannot bypass tool/approval boundaries.

## Constraints
- All sub-agent tool calls route through the same router.
- Side-effect approvals for sub-agent calls must use mailbox escalation flow.

## Related Documents
- `docs/03_agent/mailbox-and-approval-flow.md`
- `docs/05_tools/confirmation-and-side-effect-policy.md`
