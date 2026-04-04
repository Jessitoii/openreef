# 01  Product Requirements Document (PRD)

## Vision & Positioning
**OpenReef** is a fully offline, fully client-side personal AI agent exclusively for Android. There is no server, no subscription, and no data leaves the device.
The model runs directly on-device using LiteRT-LM, user memory is stored locally via `sqlite-vec`, external integrations connect through MCP (Model Context Protocol), and native Android capabilities are directly exposed as agent tools.

OpenReef is designed as the mobile-native, privacy-first answer to OpenClaw.

### Comparison with OpenClaw
| Dimension | OpenClaw | OpenReef |
| :--- | :--- | :--- |
| **Runtime** | PC/Mac server + phone as UI | Phone IS the server |
| **Inference** | Cloud API (Claude, GPT, etc.) | On-device LiteRT-LM |
| **Model Format** | API calls (stateless) | `.litertlm` — GPU/NPU accelerated |
| **Privacy** | Self-hosted but PC-dependent | Zero data leaves device |
| **Always-on** | PC must be running | Android Foreground Service |
| **Shell Access** | Full shell on host OS | MCP tool abstraction + native tools |
| **Wake Word** | macOS voice wake | Porcupine on Android |
| **Target User** | Developers with a PC | Anyone with an Android phone |

## Design Philosophy
*   **Terminal-Aesthetic UI:** Inspired by the Claude Code CLI, featuring JetBrains Mono font, a sleek dark theme, coral accents, and minimal chrome.
*   **Mascot Identity:** A pixel art lobster (or similar) offering a playful brand above serious underlying technology.
*   **Open Source Core:** MIT License for the core open-source version, with an optional Play Store premium layer for monetization.
*   **Agent Skills Standard:** Follows the open standard for Agent Skills (the same format as Claude Code / OpenClaw).
*   **Community First:** Supports a community skill marketplace, a custom MCP registry, and aggressive contributor recognition.

## Pricing & Monetization Strategy
| Layer | Details |
| :--- | :--- |
| **GitHub / Build Yourself** | 100% Free. Full features, MIT license, no artificial limits. |
| **Play Store (Free Tier)** | Free. Core features, standard models included, OpenReef branding. |
| **Play Store (Premium)** | One-time purchase / Sub. Priority model updates, curated skill packs, Kokoro TTS. |
| **Skill Marketplace** | Revenue share. Community skills can be free or paid (70/30 split). |

## Open Questions for v1.0
1.  **Final Project Name:** OpenReef (Current working title), Pincer, or TBD?
2.  **Dart MCP Client:** Port community `mcp-dart` or write a minimal one from scratch?
3.  **Porcupine Licensing:** Free for OSS, requires discussion for the commercial Play Store tier.
4.  **Skill Marketplace Hosting:** GitHub JSON index vs Hosted API.
5.  **Premium Tier Pricing:** One-time €4.99 or monthly €1.99, or pure freemium?
6.  **Mascot Design:** Pixel art lobster, minimal line art, or ASCII lobster?
7.  **Skill Security Process:** Maintainer review, automated scanner, or signature-only trust?
