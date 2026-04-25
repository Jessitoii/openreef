# AGENTS.md

## Project
OpenReef is an offline-first AI agent mobile application built with Flutter.
Core system includes:
- Agent engine (planning + execution)
- Memory system (context + persistence)
- Tool/skill execution layer
- MCP integration
- Flutter UI layer

The app is NOT a generic Flutter app. It is an agent-driven system. All changes must respect this.

---

## Architecture (STRICT)
Follow docs/02_system/system-overview.md exactly.

Allowed top-level structure:
- lib/agent/
- lib/context/
- lib/mcp/
- lib/skills/
- lib/memory/
- lib/tools/
- lib/ui/

Rules:
- Do NOT create new top-level folders
- Do NOT move modules between domains
- Do NOT redesign architecture
- Do NOT introduce alternative patterns

If something does not fit → adapt inside existing modules

---

## Code Rules (STRICT)

- Do NOT modify unrelated files
- Do NOT perform large refactors
- Do NOT add new dependencies unless absolutely required
- Prefer extending existing classes over creating new systems
- Keep functions small and focused
- Avoid over-engineering

Naming:
- files → snake_case
- classes → UpperCamelCase
- methods/variables → lowerCamelCase

---

## Agent System Rules (CRITICAL)

- Agent logic MUST stay inside `lib/agent/`
- Memory logic MUST stay inside `lib/memory/`
- Tool execution MUST stay inside `lib/tools/`
- UI MUST NOT contain business logic

Do NOT mix these layers.

---

## Development

Commands:
flutter pub get
flutter analyze
flutter test
flutter run


Before finishing any task:
- run analyzer
- ensure no warnings
- ensure code compiles

---

## Testing

- Place tests under `test/` mirroring `lib/`
- Prioritize:
  - agent planning logic
  - tool routing
  - memory writes

---

## Verification

After every implementation:

1. Run static analysis:
   flutter analyze

2. Run tests:
   flutter test

3. If there are errors or warnings:
   - Fix them immediately
   - Do NOT leave broken code

4. Ensure:
   - Code compiles
   - No analyzer warnings
   - No failing tests

5. Do NOT proceed to next task until all checks pass

---

## What NOT to do

- Do NOT invent new architecture
- Do NOT add random abstractions
- Do NOT introduce unnecessary state management solutions
- Do NOT rewrite working code
- Do NOT guess behavior — follow docs/

---

## Source of Truth

Primary:
- docs/02_system/system-overview.md

Secondary:
- other docs/ files

If conflict exists → architecture doc wins

PRs should include a clear summary, linked issue or spec section, testing notes, and screenshots or recordings for UI changes. If a change updates architecture or behavior, also update the relevant file in [`docs/`](/D:/Software/Flutter/OpenReef/docs).
