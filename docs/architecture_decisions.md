ADR-001: Single Runtime Path
----------------------------

Status: REQUIRED

Decision:Only one inference and execution path will be used in production.

Rationale:Multiple paths increase complexity and bugs.

ADR-002: Mailbox Approval System
--------------------------------

Status: REQUIRED

Decision:All sensitive tools must pass through a centralized approval system.

Rationale:Prevents unsafe autonomous actions.

ADR-003: Semantic Memory
------------------------

Status: REQUIRED

Decision:Memory must use vector-based retrieval.

Rationale:Keyword matching is insufficient.

ADR-004: Progressive Skill Injection
------------------------------------

Status: REQUIRED

Decision:Only relevant skills are injected into context.

Rationale:Prevents context overload.

ADR-005: Trigger → Agent Execution
----------------------------------

Status: REQUIRED

Decision:Triggers must execute agent tasks, not standalone actions.

Rationale:Maintains consistent behavior.