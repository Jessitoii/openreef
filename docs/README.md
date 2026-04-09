# OpenReef Architecture Documentation

## What this tree is

This `docs/` tree is the canonical architecture and runtime contract set for OpenReef.
It is split by ownership domain so each concept has exactly one authoritative home.

## Where to start

1. `docs/00_meta/doc-map.md`
2. `docs/00_meta/architecture-principles.md`
3. `docs/00_meta/status-and-scope.md`
4. `docs/02_system/system-overview.md`

## Authoritative files by major topic

- Execution lifecycle models: `docs/02_system/execution-model.md`
- Runtime policy envelope: `docs/02_system/execution-policy.md`
- Loop step semantics: `docs/03_agent/agent-loop.md`
- Tool routing and result contract: `docs/05_tools/tool-router.md`, `docs/05_tools/tool-result-contract.md`
- Trigger arbitration and scheduling: `docs/06_triggers-automation/trigger-lifecycle.md`, `docs/06_triggers-automation/trigger-scheduler.md`
- Context and memory pipeline: `docs/04_context-memory/context-assembly.md`, `docs/04_context-memory/memory-write-discipline.md`
- Skills runtime boundaries: `docs/07_skills/skills-overview.md`, `docs/07_skills/skill-permissions-and-sandbox.md`
- Voice/mobile maturity and integration: `docs/08_voice-mobile/voice-overview.md`, `docs/08_voice-mobile/mobile-native-integration.md`

## Transitional note

`docs/intermediate-system-spec.md` is preserved as a superseded migration source and should not receive new architectural content.
