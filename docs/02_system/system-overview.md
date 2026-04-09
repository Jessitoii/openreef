# System Overview

## Purpose
Define runtime topology, ownership boundaries, and end-to-end flow.

## Scope
Covers cross-domain architecture boundaries only.

## Responsibilities
- UI (`lib/ui/`): presentation and state projection only.
- Agent core (`lib/agent/`): classification, execution coordination, shared loop invocation.
- Context (`lib/context/`): planning, retrieval, reduction, rendering, compaction orchestration.
- Memory (`lib/memory/`): retrieval and post-turn memory persistence.
- Tools (`lib/tools/`): adapter implementations behind router contract.
- MCP (`lib/mcp/`): external tool/event integration and secret boundary.
- Skills (`lib/skills/`): registry, activation, bounded injection.
- Triggers (`lib/triggers/`): event intake and scheduling arbitration.
- Voice/mobile (`lib/voice/`, Android): partial voice pipeline and native bridge.

## Execution Flow
1. Source intake normalizes input.
2. Classifier selects lifecycle mode.
3. Executor validates request and policy.
4. Shared loop runs actions.
5. Router/context/memory integrations execute.
6. Structured result persists and projects to UI.

## Constraints
- One engine and one loop.
- No prompt-driven lifecycle semantics.
- No bypassing policy boundaries.

## Related Documents
- `docs/02_system/execution-model.md`
- `docs/03_agent/agent-loop.md`
