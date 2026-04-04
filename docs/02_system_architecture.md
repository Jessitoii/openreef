# 02  System Architecture

## Layer Diagram

```mermaid
flowchart TD
    UI[Flutter UI Layer\nChat · Skills · MCP · Model Manager · Settings]
    
    subgraph Core[Agent Core (Dart)]
        Planner[Planner]
        Context[Context Engine]
        Router[Tool Router]
        Scheduler[Scheduler]
    end

    Bridge[LiteRT-LM Bridge\nKotlin/C++\nGPU + NPU accel]
    MCPClient[MCP Client Layer\nConnection Pool · OAuth · Event Subscription]
    
    subgraph Storage[Skills + RAG + Memory Layer]
        SkillsR[Skills registry · progressive disclosure]
        SqliteVec[sqlite-vec · MiniLM embeddings]
        MemIndex[MEMORY.md index\nStrict Write Discipline]
    end

    System[Android System Layer\nForeground Service · AlarmManager\nNative Tools · Wake Word · AutoDream Worker]

    UI --> Core
    Core --> Bridge
    Core --> MCPClient
    Core --> Storage
    Core --> System
```

## Project Directory Structure

```text
openreef/
├── lib/
│   ├── agent/          # Planner, agent loop, tool router, mailbox
│   ├── context/        # Context engine, assembler, compactor
│   ├── mcp/            # MCP client, connection pool, event subscriptions
│   ├── skills/         # Skill registry, loader, progressive disclosure
│   │   └── builtin/    # Built-in skill folders (each has SKILL.md)
│   ├── memory/         # sqlite-vec, MiniLM embedder, memory manager
│   │   ├── memory_index.dart    # ★ MEMORY.md pointer index
│   │   └── memory_former.dart   # + Strict Write Discipline
│   ├── tools/          # Tool registry, native tool implementations
│   ├── models/         # Model manifest, downloader, RAM/NPU checker
│   ├── triggers/       # Trigger system, standing orders, MiniKAIROS
│   ├── background/     # Foreground service, alarm manager, WorkManager
│   │   └── auto_dream_worker.dart  # ★ Nightly memory consolidation
│   ├── voice/          # Wake word, STT (Whisper), TTS
│   ├── settings/       # Settings schema, settings_tool
│   └── ui/             # Flutter screens + widgets
├── android/
│   └── app/src/main/kotlin/
│       ├── litert/     # LiteRT-LM bridge (Kotlin + JNI)
│       ├── wake/       # Porcupine wake word service
│       └── service/    # Android Foreground Service
└── assets/
    ├── skills/         # Built-in skill SKILL.md files + resources
    └── models/         # Bundled MiniLM embedding model
```

## LiteRT-LM Inference Engine

LiteRT-LM is Google's production-ready, open-source inference framework for on-device LLMs (replacing the deprecated MediaPipe LLM Inference API). It powers Gemini Nano and supports GPU/NPU acceleration, function calling, multimodality, and KV-cache management.

### Model Marketplace

| Model | Format | Size | Context | Min RAM | Best For |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Gemma 4 E2B IT** | `.litertlm` | ~1.5GB | 32k | 3GB | Default — fast, everyday queries |
| **Gemma 4 4B IT** | `.litertlm` | ~2.5GB | 32k | 4GB | Higher quality text generation |
| **Gemma 3N E2B IT** | `.litertlm` | ~1.5GB | 8k | 3GB | Multimodal (vision + audio) |
| **Gemma 3 1B IT** | `.litertlm` | ~700MB | 8k | 2GB | Low-end devices |
| **Phi-4 Mini IT** | `.litertlm` | ~2.1GB | 16k | 4GB | Reasoning tasks / ULTRAPLAN |
| **Qwen 3 1.7B IT** | `.litertlm` | ~1.1GB | 8k | 3GB | Multilingual focus |

### Android Model Bootstrap

OpenReef resolves its primary LiteRT model from the Android application's internal documents directory instead of relying on a bundled asset or an ADB sideload path.

Boot flow:

- on startup, the models layer checks the internal `models/` directory for a completed downloaded model
- if no model is present, the UI is trapped on a dedicated Model Download screen
- downloads use HTTP range requests with resumable `.part` files so multi-GB transfers can continue safely
- once a model is present locally, the absolute file path is passed into `LiteRtBridge.initModel(path: ...)`

Ownership remains strict:

- `lib/models/` owns registry metadata, storage resolution, resume logic, and hardware-fit checks
- `lib/ui/` renders the marketplace and progress UI only
- agent boot continues only after LiteRT has been initialized with a local on-disk model
