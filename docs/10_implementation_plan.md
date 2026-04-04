# 10  Implementation Execution Plan

## Build Order

### Phase 1 — Foundation (Weeks 1-3)
*   **Week 1**: Flutter project scaffold, Kotlin LiteRT-LM bridge setup, inference streaming into Flutter, basic chat UI in a terminal aesthetic.
*   **Week 2**: `sqlite-vec` integration, Context Engine Assembly pipeline, `MEMORY.md` Pointer Index, and Strict Write Discipline implementation.
*   **Week 3**: MCP client connections (Google Calendar, Gmail OAuth), Tool Router, and Android Foreground Service establishment.

### Phase 2 — Skills & Automation (Weeks 4-5)
*   **Week 4**: Skill registry loader, 10 MVP built-in skills, Skill-Creator MVP, and the integration of MiniKAIROS proactive trigger evaluation.
*   **Week 5**: AlarmManager precise alarms, MCP Event triggers (SSE), Standing Orders, Settings Tool, and the Multi-Agent Isolate Spawning. AutoDream worker background task setup.

### Phase 3 — Polish & Launch (Week 6)
*   **Week 6**: Finalize native tools, RAM/NPU capability checking, Skill Security Sandbox Mode and Permission Manifest, localization, and public `v0.1` GitHub release.

## Lessons from Claude Code Leak
The architecture directly internalizes 6 critical architectural lessons from the March 31, 2026 Claude Code source code leakage incident.

| # | Claude Code Lesson | OpenReef Implementation | Document Ref |
| :--- | :--- | :--- | :--- |
| **1** | Memory context entropy. | `MEMORY.md` lightweight index appended to every system prompt. | `03_core_agent_engine.md` |
| **2** | Background consolidation resolves contradictions. | `AutoDreamWorker` running nightly. | `03_core_agent_engine.md` |
| **3** | Unsuccessful tools corrupt memory. | Strict Write Discipline: `failedToolCalls` aborts extraction. | `03_core_agent_engine.md` |
| **4** | Chronological triggers ignore context. | MiniKAIROS proactive contextual evaluation before executing triggers. | `05_tools_and_triggers.md` |
| **5** | Complex tasks exhaust small models. | Task-Aware Model Routing (e.g. Phi-4 Mini for complex planning). | `04_multi_agent_system.md` |
| **6** | Community supply chain risks via skills. | `SkillSandbox` constraints and compulsory `tools_required` manifest. | `07_skills_ecosystem.md` |
