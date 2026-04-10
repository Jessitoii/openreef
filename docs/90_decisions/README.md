# Architecture Decision Records (ADRs)

This directory contains normalized architectural decisions for OpenReef.

## ADR Index

| ADR | Title | Status | Summary | File |
|---|---|---|---|---|
| ADR-001 | Unified Execution Model | Accepted | One executor + one shared loop with explicit lifecycle semantics. | [ADR-001-unified-execution-model.md](./ADR-001-unified-execution-model.md) |
| ADR-002 | Single Runtime Path via Dart LiteRtBridge | Accepted | Production runtime path is singular and Dart-side. | [ADR-002-single-runtime-path-dart-litert-bridge.md](./ADR-002-single-runtime-path-dart-litert-bridge.md) |
| ADR-003 | Mailbox Escalation for Sub-Agent Approvals | Accepted | Sub-agent approvals resolve via mailbox transport with centralized policy authority. | [ADR-003-mailbox-escalation-for-sub-agent-approvals.md](./ADR-003-mailbox-escalation-for-sub-agent-approvals.md) |
| ADR-004 | Vector-Semantic Memory Retrieval | Accepted | Memory retrieval uses semantic ranking rather than keyword-only matching. | [ADR-004-vector-semantic-memory-retrieval.md](./ADR-004-vector-semantic-memory-retrieval.md) |
| ADR-005 | Progressive Skill Injection by Relevance and Budget | Accepted | Skills are injected selectively per turn under budget/policy. | [ADR-005-progressive-skill-injection.md](./ADR-005-progressive-skill-injection.md) |
| ADR-006 | Triggered Work Must Route Through Agent Execution | Accepted | Trigger work uses unified executor path, not standalone execution. | [ADR-006-triggered-work-must-route-through-agent-execution.md](./ADR-006-triggered-work-must-route-through-agent-execution.md) |
| ADR-007 | Agent Loop Hardening and Deterministic Terminal States | Accepted | Loop remains bounded with deterministic freeze/fail behavior. | [ADR-007-agent-loop-hardening-and-deterministic-terminals.md](./ADR-007-agent-loop-hardening-and-deterministic-terminals.md) |
| ADR-008 | MCP Secret Boundary and Endpoint Trust | Accepted | MCP secrets remain in secure storage with explicit trust validation. | [ADR-008-mcp-secret-boundary-and-endpoint-trust.md](./ADR-008-mcp-secret-boundary-and-endpoint-trust.md) |
| ADR-009 | Single Tool Router Dispatch Boundary | Accepted | All tool classes execute through one router boundary. | [ADR-009-single-tool-router-dispatch-boundary.md](./ADR-009-single-tool-router-dispatch-boundary.md) |
| ADR-010 | Normalized ToolResult Contract | Accepted | Tool outcomes use a closed, normalized status contract. | [ADR-010-normalized-tool-result-contract.md](./ADR-010-normalized-tool-result-contract.md) |
| ADR-011 | Standing Orders as Structured Runtime Rules | Accepted | Standing orders are machine-evaluable rules, not prompt prose. | [ADR-011-standing-orders-as-structured-runtime-rules.md](./ADR-011-standing-orders-as-structured-runtime-rules.md) |
| ADR-012 | AutoDream Must Not Be Authoritative for Core Correctness | Accepted | AutoDream remains optional and maturity-gated. | [ADR-012-autodream-non-authoritative-for-core-correctness.md](./ADR-012-autodream-non-authoritative-for-core-correctness.md) |

## Backlog (Not Yet ADR)

These items are unresolved architectural choices and remain backlog candidates until decided:

1. Run/workflow persistence schema and versioning strategy.
2. Execution classifier strategy split (rules-only vs structured assist).
3. Final default policy constants by source class (duplicate/queue/retry/timeout/priority).
4. Trigger scheduler grace-window and jitter tolerance defaults.
5. Canonical permission subject/resource taxonomy for cross-domain reporting.

Related implementation gaps are tracked in [docs/99_gaps/README.md](../99_gaps/README.md).
