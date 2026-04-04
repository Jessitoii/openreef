# 🦞 OpenReef

**A Fully Offline, Client-Side Personal AI Agent for Android.**

OpenReef is a complete, mobile-native and privacy-first answer to server-dependent agent protocols like OpenClaw. There is no cloud server, no subscription, and strictly zero data that implicitly leaves your device. 

The inference model runs entirely on-device via **LiteRT-LM** (accelerated by the GPU/NPU), memory is persistently stored locally via **sqlite-vec**, and it integrates directly with your digital life through **Model Context Protocol (MCP)** and native Android tool APIs.

---

## 🌟 Key Features

- **On-Device Inference**: Powered by LiteRT-LM. Run models like Gemma 4 (E2B/4B) or Phi-4 Mini natively utilizing the phone's GPU/NPU, keeping conversations totally private.
- **Always-on Voice Interface**: Zero-cloud wake word detection powered by Porcupine ("Hey OpenReef") + Whisper Tiny on-device STT transcribe engine. 
- **Native Android Tools**: Direct integration with over 37+ Android capabilities (Camera, Contacts, SMS, Alarms, Location) accessible natively by the agent.
- **Model Context Protocol (MCP)**: Bring Your Own Integrations. Built-in support to seamlessly connect to external APIs like Google Calendar, Gmail, GitHub, Notion, or Home Assistant under user-controlled OAuth.
- **Multi-Agent System**: Internal Agent Client Protocol implementation. A main agent can autonomously spawn child sub-agents in isolated Dart threads with custom model routing to parallelize complex tasks.
- **Skills Ecosystem**: The agent is extensible via Markdown-based `SKILL.md` rules. Contains **Skill-Creator**, a unique meta-skill allowing the LLM to design and learn new skills, workflows, and memory schemas purely through conversation.
- **Proactive Automation (MiniKAIROS)**: Triggers aren't just dumb crons. The agent contextually evaluates its environment (Foreground state, Battery, Running Sub-agents) before interrupting you or running background tasks.
- **Self-Healing Long Term Memory**: Employs a strict write discipline and asynchronous `AutoDreamWorker` nightly consolidation to solve context entropy.

---

## 🏗️ Architecture Stack

*   **UI Layer**: Flutter (Terminal-Aesthetic UI, JetBrains Mono font).
*   **Agent Core**: Dart-based Planner, Context Assembler, Tool Router, and Multi-Agent Tracker.
*   **Inference Bridge**: Kotlin / C++ JNI bridge talking directly to the `LiteRtLMEngine`.
*   **Vector Storage**: `sqlite-vec` combined with quantized MiniLM embedding models.
*   **Background Activity**: Android Foreground Services, WorkManager, and AlarmManager.

---

## 📖 Deep-Dive Documentation

For developers, contributors, or users looking to understand how the internal engine operates, the `docs/` folder contains comprehensive industry-standard documentation covering all subsystems:

1. [Product Requirements Document (PRD)](docs/01_product_requirements_document.md)
2. [System Architecture (Layer Diagrams)](docs/02_system_architecture.md)
3. [Core Agent Engine (Agent Loop, Context, Memory)](docs/03_core_agent_engine.md)
4. [Multi-Agent System & ACP](docs/04_multi_agent_system.md)
5. [Tools and Triggers (MiniKAIROS)](docs/05_tools_and_triggers.md)
6. [Prompt Library & Assembly](docs/06_prompt_library.md)
7. [Skills Ecosystem (Skill-Creator, Sandboxing)](docs/07_skills_ecosystem.md)
8. [Voice Interface and Settings](docs/08_voice_interface_and_settings.md)
9. [Bridge Specification (Flutter <-> Kotlin / JNI)](docs/09_bridge_specification.md)
10. [Implementation Execution Plan](docs/10_implementation_plan.md)

---

## 🛡️ Privacy & Supply Chain Security

OpenReef was built adopting heavy operational security lessons. OpenReef uses a strict **Skill Sandboxing Model** and mandatory `tools_required` manifests. Unverified community skills run in locked memory scopes with explicit UX permission requests to guard against Prompt Injection and external exfiltration attempts.

## 🤝 Open Source & Licensing

The core OpenReef module is open-source software under the **MIT License**.

Whether you want to build custom MCP servers, author robust JSON/Markdown Agent Skills, or optimize the LiteRT bridge — community contributions are highly encouraged!
