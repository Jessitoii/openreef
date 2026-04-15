import 'package:openreef/agent/agent_orchestrator.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/triggers/trigger_repository.dart';

/// Immutable unified execution context passed to ALL tool handlers.
class ToolExecutionContext {
  const ToolExecutionContext({
    DateTime Function()? clock,
    required this.sessionKey,
    this.memoryStore,
    this.memoryIndex,
    this.settingsController,
    this.triggerRepository,
    this.mailbox,
    this.orchestrator,
  }) : _clock = clock;

  final DateTime Function()? _clock;

  /// The session key of the currently executing agent.
  final String sessionKey;

  /// Memory persistence layer.
  final MemoryStorage? memoryStore;

  /// Memory index.
  final MemoryIndex? memoryIndex;

  /// Settings.
  final SettingsController? settingsController;

  /// Triggers.
  final TriggerRepository? triggerRepository;

  /// Mailbox.
  final AgentMailbox? mailbox;

  /// Agent Orchestrator.
  final AgentOrchestrator? orchestrator;

  DateTime now() => _clock?.call() ?? DateTime.now().toUtc();
}
