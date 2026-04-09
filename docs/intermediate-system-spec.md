# OpenReef Intermediate System Specification (Archived Transitional Document)

## Why this file exists

This file was created as an intermediate consolidation step to reconstruct a truth-aligned architecture contract from fragmented legacy material.

## Migration outcome

Its contract content has been migrated into the canonical multi-file docs tree.
This file is now archival-only and should not be used as an implementation authority.

## Canonical documentation by topic

- System topology: [System Overview](./02_system/system-overview.md)
- Execution lifecycle models: [Execution Model](./02_system/execution-model.md)
- Runtime policy defaults: [Execution Policy](./02_system/execution-policy.md)
- Loop behavior: [Agent Loop](./03_agent/agent-loop.md)
- Session projection: [Session Lifecycle](./03_agent/session-lifecycle.md)
- Tool dispatch: [Tool Router](./05_tools/tool-router.md)
- Tool outcomes: [Tool Result Contract](./05_tools/tool-result-contract.md)
- Confirmation policy: [Confirmation and Side-Effect Policy](./05_tools/confirmation-and-side-effect-policy.md)
- Sub-agent escalation transport: [Mailbox and Approval Flow](./03_agent/mailbox-and-approval-flow.md)
- Trigger arbitration: [Trigger Lifecycle](./06_triggers-automation/trigger-lifecycle.md)
- Trigger timing mechanics: [Trigger Scheduler](./06_triggers-automation/trigger-scheduler.md)
- Context compiler flow: [Context Assembly](./04_context-memory/context-assembly.md)
- Memory store architecture: [Memory Architecture](./04_context-memory/memory-architecture.md)
- Memory write reliability: [Memory Write Discipline](./04_context-memory/memory-write-discipline.md)
- Skills runtime boundary: [Skills Overview](./07_skills/skills-overview.md)

## Decisions and gaps

- Architectural choices pending decision: [90_decisions/README.md](./90_decisions/README.md)
- Known implementation gaps: [99_gaps/README.md](./99_gaps/README.md)

## Authority rule

If any statement in this archived file conflicts with canonical files, canonical files win.
