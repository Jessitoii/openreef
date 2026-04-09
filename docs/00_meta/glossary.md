# Glossary

- **ExecutionInput**: normalized intake envelope created from chat, trigger, resume, system, or MCP event sources.
- **ExecutionRequest**: sole executor input containing mode, payload, and bound policy.
- **ExecutionPolicy**: runtime behavior envelope controlling tool use, persistence, suspend, duplication, queueing, retries, timeouts, and completion visibility.
- **RunState**: authoritative persisted lifecycle record for non-ephemeral runs.
- **WorkflowDefinition**: static workflow template with versioned rules and default policy.
- **WorkflowRun**: persisted runtime instance bound to a workflow snapshot.
- **ExecutionResult**: terminal structured outcome emitted by executor for each request.
- **ToolCall**: normalized tool invocation request routed through the single router.
- **ToolResult**: normalized tool execution outcome with canonical status categories.
- **TriggerEvent**: normalized trigger fire payload with dedupe/coalesce key.
- **StandingOrderRule**: structured runtime rule applied during trigger/event handling.
- **SkillDefinition**: installable skill metadata + permissions + injection descriptor.
- **SkillRuntimeState**: per-skill runtime administrative state (install/enable/trust/health).
- **SkillActivationDecision**: per-turn decision to activate/skip a skill with reason.
- **ContextPlan**: section-level token and retrieval plan for context assembly.
- **CompiledContextPackage**: rendered context payload passed to loop consumption.
- **MemoryWriteCandidate**: post-turn extracted candidate memory item with reliability flags.
- **CompactionResult**: result of context compaction pass including level and fallback status.
