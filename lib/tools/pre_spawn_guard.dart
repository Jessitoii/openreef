import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/agent/agent_models.dart';

enum PreSpawnDecisionKind {
  allow,
  denyDuplicateActive,
  denyPolicyViolation,
  denyRiskHigh,
  reuseExisting,
}

class PreSpawnDecision {
  const PreSpawnDecision.allow() : kind = PreSpawnDecisionKind.allow, reason = null;
  const PreSpawnDecision.deny(this.kind, this.reason);
  const PreSpawnDecision.reuse(this.reason) : kind = PreSpawnDecisionKind.reuseExisting;

  final PreSpawnDecisionKind kind;
  final String? reason;
}

class PreSpawnGuard {
  Future<PreSpawnDecision> evaluate({
    required String task,
    required String sessionKey,
    required MemoryStorage memoryStore,
    required SettingsController settings,
    // Add additional dependencies later like RunStateStore or SessionStore
  }) async {
    // Basic heuristics:
    // 1. Check if same task is actively running
    // 2. Policy limit
    // 3. Risk checks

    return const PreSpawnDecision.allow();
  }
}
