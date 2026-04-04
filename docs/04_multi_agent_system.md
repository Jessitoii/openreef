# 04  Multi-Agent System

OpenReef implements the Agent Client Protocol (ACP) internally for orchestrating sub-agents through Dart Isolates.

## Depth Model

| Depth | Session Key | Role | Can Spawn? | Tool Profile |
| :--- | :--- | :--- | :--- | :--- |
| **0** | `agent:main` | Main Agent — always running | Always | full |
| **1** | `agent:main:sub:<uuid>` | Orchestrator / Specialist | If maxDepth≥2 | configurable |
| **2** | `agent:main:sub:<u1>:sub:<u2>` | Worker / Leaf | Never | minimal |

## Task-Aware Model Routing
Spawned sub-agents receive an automatic model override based on the complexity of their task. This ensures smaller models answer simple queries, preserving battery and RAM.

| Complexity | Selected Model | Thinking Level | Use Case |
| :--- | :--- | :--- | :--- |
| **Heavy** | `phi4-mini` | `deep` | Deep analysis, document review |
| **Normal** | `gemma4-e2b` | `balanced` | Standard sub-agent flows |
| **Light** | `gemma3-1b` | `fast` | Notifications, rapid memory lookups |

## Mailbox Pattern (Coordinator Approval)
A sub-agent (Worker) cannot execute potentially dangerous operations independently. If a tool requires confirmation (e.g., `sms_send`, `phone_call`), the sub-agent routes the request to the main agent's mailbox instead of executing it directly.

```dart
// lib/agent/tool_router.dart
Future toolRouter.dispatch(ToolCall call, {required String sessionKey}) async {
  final tool = registry.get(call.toolId);
  
  if (tool.requiresConfirmation) {
    if (sessionKey == 'agent:main') {
      final ok = await userConfirm(call);
      if (!ok) return ToolResult.rejected;
    } else {
      // Sub-agent → send to mailbox, wait for coordinator (main agent)
      final decision = await mailbox.requestApproval(
        workerSessionKey: sessionKey,
        call: call,
      );
      if (decision == MailboxDecision.rejected) {
        return ToolResult.rejected;
      }
    }
  }
  return tool.execute(call);
}
```

## Concurrency & Resource Limits
Due to mobile context restrictions, sub-agents run in separate Dart Isolates. Loading a different model per sub-agent consumes high RAM.
- **Max Spawn Depth**: `3`
- **Max Children Per Agent**: `3`
- **Max Concurrent SubAgents**: `2` (Pre-checked against device RAM).
- **SubAgent Timeout**: `300s`
- **Cascade Stop**: Terminating a parent sub-agent naturally terminates all its isolate children.
