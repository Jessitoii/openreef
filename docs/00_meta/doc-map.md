# Documentation Map

| Concept | Authoritative File | Notes |
|---|---|---|
| Runtime topology and domain boundaries | [02_system/system-overview.md](../02_system/system-overview.md) | One engine, one loop, strict layer ownership. |
| Execution input/request/run/result models | [02_system/execution-model.md](../02_system/execution-model.md) | Defines lifecycle models and state machine. |
| Queue/duplicate/retry/timeout/suspend/completion policy | [02_system/execution-policy.md](../02_system/execution-policy.md) | Policy defaults and legality envelope. |
| Loop steps and continuation/termination | [03_agent/agent-loop.md](../03_agent/agent-loop.md) | Loop authority and strict step order. |
| Session and run lifecycle projection | [03_agent/session-lifecycle.md](../03_agent/session-lifecycle.md) | Session-visible lifecycle and projection rules. |
| Multi-agent role boundaries | [03_agent/multi-agent-architecture.md](../03_agent/multi-agent-architecture.md) | Main vs sub-agent separation. |
| Mailbox escalation transport/lifecycle | [03_agent/mailbox-and-approval-flow.md](../03_agent/mailbox-and-approval-flow.md) | Sub-agent escalation transport only. |
| Context planning/retrieval/reduction/render path | [04_context-memory/context-assembly.md](../04_context-memory/context-assembly.md) | Canonical context compiler contract. |
| Compaction levels and fallback behavior | [04_context-memory/compaction-strategy.md](../04_context-memory/compaction-strategy.md) | Micro/auto/full compaction policy. |
| Memory stores and pointer/index role | [04_context-memory/memory-architecture.md](../04_context-memory/memory-architecture.md) | Retrieval and storage boundaries. |
| Memory write reliability rules | [04_context-memory/memory-write-discipline.md](../04_context-memory/memory-write-discipline.md) | Normative acceptance/rejection criteria. |
| AutoDream maturity boundary | [04_context-memory/autodream.md](../04_context-memory/autodream.md) | Explicit non-operational production status. |
| Tool catalog | [05_tools/tools-overview.md](../05_tools/tools-overview.md) | Tool classes and ownership summary. |
| Single dispatch contract | [05_tools/tool-router.md](../05_tools/tool-router.md) | Validation, policy checks, adapter routing. |
| Confirmation and side-effect policy authority | [05_tools/confirmation-and-side-effect-policy.md](../05_tools/confirmation-and-side-effect-policy.md) | Global confirmation classes/rules. |
| Tool result normalization contract | [05_tools/tool-result-contract.md](../05_tools/tool-result-contract.md) | Required statuses and persistence/context rules. |
| Trigger overview | [06_triggers-automation/triggers-overview.md](../06_triggers-automation/triggers-overview.md) | Trigger source classes and intent. |
| Trigger lifecycle and arbitration matrix | [06_triggers-automation/trigger-lifecycle.md](../06_triggers-automation/trigger-lifecycle.md) | Dedupe/queue/reject/replace/coalesce. |
| Trigger scheduling mechanics | [06_triggers-automation/trigger-scheduler.md](../06_triggers-automation/trigger-scheduler.md) | Timing, missed-fire, drift, backpressure. |
| Standing-order runtime representation | [06_triggers-automation/standing-orders.md](../06_triggers-automation/standing-orders.md) | Structured rule objects, not prompt prose. |
| Skill registry and activation boundary | [07_skills/skills-overview.md](../07_skills/skills-overview.md) | Boundary summary and maturity status. |
| Skill state transitions | [07_skills/skill-lifecycle.md](../07_skills/skill-lifecycle.md) | install/enable/disable/activate transitions. |
| Skill permissions and sandboxing | [07_skills/skill-permissions-and-sandbox.md](../07_skills/skill-permissions-and-sandbox.md) | Manifest enforcement and trust levels. |
| Skill-Creator relationship | [07_skills/skill-creator.md](../07_skills/skill-creator.md) | Creation flow and runtime boundary. |
| Voice maturity and scope | [08_voice-mobile/voice-overview.md](../08_voice-mobile/voice-overview.md) | Partial/experimental status. |
| Wake/STT/VAD/TTS chain | [08_voice-mobile/wake-word.md](../08_voice-mobile/wake-word.md) | Execution chain contract when enabled. |
| Mobile native bridge boundaries | [08_voice-mobile/mobile-native-integration.md](../08_voice-mobile/mobile-native-integration.md) | Android/service/permissions integration. |
| Model runtime (intentionally minimal boundary note) | [09_models/model-runtime.md](../09_models/model-runtime.md) | Not the primary detail surface for lifecycle/tool policy. |
| Permission model (intentionally minimal global scope) | [10_security/permissions-model.md](../10_security/permissions-model.md) | Core enforcement principles with links to tool policy docs. |
| Trust boundaries | [10_security/trust-boundaries.md](../10_security/trust-boundaries.md) | Cross-domain security boundaries. |
| Migration execution plan | [12_delivery/migration-plan.md](../12_delivery/migration-plan.md) | Controlled migration steps and checks. |
| Architectural decisions backlog | [90_decisions/README.md](../90_decisions/README.md) | Unresolved decision items. |
| Implementation gaps backlog | [99_gaps/README.md](../99_gaps/README.md) | Known partial implementation coverage. |
