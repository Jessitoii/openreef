# 05  Tools and Triggers

## Native Android Tools
OpenReef possesses 37+ built-in native tools adapted for Android. These allow the LLM direct access to system components without a server.

| Category | Tools | Confirm Required | Phase |
| :--- | :--- | :--- | :--- |
| **Communication** | `phone_call`, `phone_dial`, `sms_send`, `sms_draft`, `whatsapp_draft`, `email_draft`, `contact_read`, `contact_create` | Most | MVP |
| **System** | `app_open`, `app_list`, `volume_set`, `brightness_set`, `wifi_toggle`, `dnd_set`, `battery_info`, `screen_lock` | Yes for critical | MVP |
| **Media** | `camera_photo`, `camera_scan`, `gallery_pick`, `tts_speak`, `media_play`, `audio_record` | No | MVP/v1.1 |
| **Location** | `location_get`, `maps_navigate`, `maps_search`, `geofence_add` | No | v1.1 |
| **Compute** | `math_eval`, `regex_eval`, `code_run` (sandboxed) | No | MVP |
| **Agent / Memory** | `agent_spawn`, `agent_list`, `agent_send`, `session_history`, `memory_save`, `memory_search` | No | MVP |

## Model Context Protocol (MCP) Integration
OpenReef acts as an MCP Client. Connections happen via HTTP/SSE. 

| Service | Supported MCP Tools | Handled SSE Events | Auth Type |
| :--- | :--- | :--- | :--- |
| **Google Calendar**| list, create, update, delete | None | OAuth 2.0 |
| **Gmail** | search, read, draft, send | `message_received` | OAuth 2.0 |
| **GitHub** | issues, PRs, repos | `pr_merged`, `issue_opened` | PAT |
| **Home Assistant** | control devices, states | `motion_detected` | Long-lived Token |

## Trigger System
The agent can listen to events and trigger tasks proactively in the background. Users set these up via natural language.

| Type | Example | Backing API |
| :--- | :--- | :--- |
| **SCHEDULE** | "Every day at 8am send briefing" | `AlarmManager` |
| **INTERVAL** | "Every 30 minutes check inputs" | `WorkManager` |
| **MCP_EVENT** | "When a GitHub PR is merged..." | SSE Stream (Push) |
| **STANDING_ORDER**| "Always reply to boss emails within 1hr" | Always-on rule eval |

### MiniKAIROS: Proactive Trigger Evaluation
MiniKAIROS prevents triggers from executing blindly chronologically (like simple crons) by evaluating context first.

```dart
// lib/triggers/mini_kairos.dart
Future<KairosDecision> evaluate(TriggerConfig trigger) async {
  final context = await _gatherContext();

  if (!context.isAppForeground && trigger.requiresUserAttention) {
    return KairosDecision.delay(until: AppOpenEvent);
  }
  if (context.batteryLevel < 10 && trigger.isExpensive) {
    return KairosDecision.skip(reason: 'battery_low');
  }
  if (context.activeSubAgents >= maxConcurrent) {
    return KairosDecision.queue(priority: trigger.priority);
  }
  
  return KairosDecision.proceed();
}
```
