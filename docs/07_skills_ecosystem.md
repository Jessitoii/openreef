# 07  Skills Ecosystem

OpenReef's skill system follows the Agent Skills open standard. A skill is a folder containing a `SKILL.md` file with YAML frontmatter, providing the LLM with progressive disclosure.

## Skill-Creator (The Meta-Skill)
`Skill-Creator` is the most important built-in skill. It handles the LLM's ability to logically construct new skills via natural language conversations with the user.

1. **Phase 1: Understand:** Parses user intent and required tools.
2. **Phase 2: Design:** Drafts `SKILL.md` content and trigger configs.
3. **Phase 3: Preview:** Wait for user confirmation.
4. **Phase 4: Create:** Writes to `skills/` directory and registers in the SkillRegistry.

## Skill Output Format

### SKILL.md Example
```markdown
---
tools_required: [alarm_set, memory_search]
memory_access: read_only
network_access: false
---

# Sleep Tracker
> Tracks daily sleep schedule.

## Triggers
Every day at 7am

## Behavior
1. Use `alarm_set`
2. Save using `memory_save`
```

### skill.yaml Structure (Optional)
```yaml
id: sleep_tracker
version: 1.0.0
author: user
permissions:
  tools: [memory_save, memory_search, notify, alarm_set]
  memory_scope: skill_only  # strict sandbox
  network_access: false
  background_execution: true
```

## Security & Supply Chain Defense
Based on Snyk ToxicSkills research and the Claude Code source code learnings, community skills require strict defense mechanisms against supply-chain attacks.

### 1. Mandatory Tool Manifest
Every skill MUST declare `tools_required`. Calling an undeclared tool throws a sandbox violation exception.

### 2. Skill Sandbox Mode
Community-installed skills run in a sandboxed mode:
```dart
class SkillSandbox {
  final allowedTools = skill.manifest.tools_required;
  // Memory is isolated to skill:{skill_id}:* namespace
}
```

### 3. User Approval Flow
When installing a community skill, the UI explicitly lists the permission requirements:
> "This skill requests access to: memory_search, alarm_set"

### 4. Code / Integrity Scanning (v1.1+)
PRs to the marketplace undergo static analysis for dangerous API signatures and hidden background triggers before merging.
