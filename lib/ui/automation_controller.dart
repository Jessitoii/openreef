import 'package:flutter/foundation.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/triggers/trigger_repository.dart';
import 'package:openreef/triggers/trigger_system.dart';
import 'package:openreef/ui/automation_models.dart';

class AutomationController extends ChangeNotifier {
  AutomationController({
    required TriggerRepository repository,
    required TriggerSystem triggerSystem,
  })  : _repository = repository,
        _triggerSystem = triggerSystem;

  final TriggerRepository _repository;
  final TriggerSystem _triggerSystem;

  bool _initialized = false;
  bool _loading = false;
  bool _refreshing = false;
  String? _errorMessage;
  List<TriggerConfig> _persisted = const <TriggerConfig>[];
  Map<String, TriggerConfig> _persistedById = const <String, TriggerConfig>{};
  Map<String, TriggerConfig> _runtimeById = const <String, TriggerConfig>{};
  Map<String, TriggerState> _statesById = const <String, TriggerState>{};

  bool get isLoading => _loading;
  bool get isRefreshing => _refreshing;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = _persisted.isEmpty;
    _refreshing = _persisted.isNotEmpty;
    notifyListeners();
    try {
      _persisted = await _repository.loadAll();
      _persistedById = {for (final item in _persisted) item.id: item};
      _runtimeById = {for (final item in _triggerSystem.listTriggers()) item.id: item};
      _statesById = _triggerSystem.listTriggerStates();
      _errorMessage = null;
    } catch (error) {
      _errorMessage = error.toString();
    } finally {
      _loading = false;
      _refreshing = false;
      notifyListeners();
    }
  }

  List<AutomationListItemViewModel> get allItems {
    final items = buildAutomationViewModelsFromRuntime();
    items.sort((left, right) {
      final categoryOrder = left.category.index.compareTo(right.category.index);
      if (categoryOrder != 0) return categoryOrder;
      return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });
    return items;
  }

  List<AutomationListItemViewModel> get timeBasedItems =>
      allItems.where((item) => item.category == AutomationCategory.timeBased).toList(growable: false);

  List<AutomationListItemViewModel> get eventStateItems =>
      allItems.where((item) => item.category == AutomationCategory.eventState).toList(growable: false);

  List<AutomationListItemViewModel> get standingOrderItems =>
      allItems.where((item) => item.category == AutomationCategory.standingOrders).toList(growable: false);

  int get enabledCount => allItems.where((item) => item.enabled).length;
  int get disabledCount => allItems.length - enabledCount;

  List<AutomationListItemViewModel> buildAutomationViewModelsFromRuntime() {
    final ids = <String>{
      ..._runtimeById.keys,
      ..._persistedById.keys,
    };
    return ids.map((id) {
      final runtime = _runtimeById[id];
      final persisted = _persistedById[id];
      final source = runtime ?? persisted;
      if (source == null) {
        throw StateError('automation_source_missing:$id');
      }
      return _buildListItem(
        trigger: source,
        runtime: runtime,
        persisted: persisted,
        state: _statesById[id],
      );
    }).toList(growable: false);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _commitAutomationChange(
      id: id,
      mutate: (trigger) => trigger.copyWith(enabled: enabled),
    );
  }

  Future<void> deleteTrigger(String id) async {
    final runtimeTrigger = _runtimeById[id];
    final persisted = _persistedById[id];
    final trigger = runtimeTrigger ?? persisted;
    if (trigger == null) return;
    final hadRuntime = runtimeTrigger != null;
    final hadPersisted = persisted != null;
    try {
      if (hadRuntime) {
        await _triggerSystem.cancel(id);
      }
      if (hadPersisted) {
        await _repository.remove(id);
      }
      await refresh();
    } catch (error) {
      if (hadPersisted && !hadRuntime) {
        await _triggerSystem.register(persisted);
      }
      _errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> saveFromDraft(AutomationEditorDraft draft) async {
    final trigger = draft.toTriggerConfig();
    await _commitAutomationChange(id: trigger.id, replacement: trigger);
  }

  Future<void> _commitAutomationChange({
    required String id,
    TriggerConfig Function(TriggerConfig current)? mutate,
    TriggerConfig? replacement,
  }) async {
    final current = _runtimeById[id] ?? _persistedById[id];
    if (current == null && replacement == null) {
      throw StateError('unknown_automation:$id');
    }
    final next = replacement ?? mutate!(current!);
    final hadRuntime = _runtimeById[id] != null;
    final previousPersisted = _persistedById[id];
    try {
      final registration = await _triggerSystem.register(next);
      if (!registration.isRegistered) {
        throw StateError(registration.error ?? 'automation_registration_failed');
      }
      await _repository.upsert(next);
      await refresh();
    } catch (error) {
      await _triggerSystem.cancel(id);
      if (hadRuntime && previousPersisted != null) {
        await _triggerSystem.register(previousPersisted);
      }
      _errorMessage = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  AutomationEditorDraft draftForCreate(AutomationEditorKind kind) {
    return AutomationEditorDraft.create(kind);
  }

  AutomationEditorDraft draftForEdit(String id) {
    final trigger = _runtimeById[id] ?? _persistedById[id];
    if (trigger == null) {
      throw StateError('unknown_automation:$id');
    }
    return AutomationEditorDraft.fromTrigger(trigger);
  }

  AutomationDetailViewModel detailFor(String id) {
    final runtime = _runtimeById[id];
    final persisted = _persistedById[id];
    final source = runtime ?? persisted;
    if (source == null) {
      throw StateError('unknown_automation:$id');
    }
    final state = _statesById[id];
    final drift = runtime == null && persisted != null
        ? AutomationDriftState.persistedNotRegistered
        : AutomationDriftState.normal;
    return _buildDetailViewModel(
      trigger: source,
      state: state,
      driftState: drift,
    );
  }

  StandingOrderDetailViewModel standingOrderDetailFor(String id) {
    final detail = detailFor(id);
    return StandingOrderDetailViewModel(
      id: detail.id,
      title: detail.title,
      enabled: detail.enabled,
      priorityLabel: detail.priorityLabel,
      conditionSummary: detail.conditionSummary,
      actionSummary: detail.actionSummary,
      appliesToSummary: detail.appliesToSummary,
      runtimeStatusLabel: detail.runtimeStatusLabel,
      driftState: detail.driftState,
      lastMatchedLabel: detail.lastMatchedLabel,
      lastAppliedLabel: detail.lastAppliedLabel,
    );
  }

  AutomationListItemViewModel _buildListItem({
    required TriggerConfig trigger,
    required TriggerConfig? runtime,
    required TriggerConfig? persisted,
    required TriggerState? state,
  }) {
    final drift = runtime == null && persisted != null
        ? AutomationDriftState.persistedNotRegistered
        : AutomationDriftState.normal;
    final status = state?.lastStatus.name ?? (runtime == null ? 'persisted_not_registered' : 'idle');
    final summary = _buildSummary(trigger);
    return AutomationListItemViewModel(
      id: trigger.id,
      title: trigger.name.isEmpty ? trigger.id : trigger.name,
      summary: summary,
      enabled: trigger.enabled,
      runtimeStatusLabel: status,
      driftState: drift,
      canEdit: _canEdit(trigger.type),
      canDelete: true,
      category: _categoryFor(trigger.type),
      subtypeLabel: _subtypeLabel(trigger.type),
      isStandingOrder: trigger.type == TriggerType.standingOrder,
      triggerType: trigger.type,
    );
  }

  AutomationDetailViewModel _buildDetailViewModel({
    required TriggerConfig trigger,
    required TriggerState? state,
    required AutomationDriftState driftState,
  }) {
    final nextRun = _buildNextRunLabel(trigger, state);
    return AutomationDetailViewModel(
      id: trigger.id,
      title: trigger.name.isEmpty ? trigger.id : trigger.name,
      category: _categoryFor(trigger.type),
      subtypeLabel: _subtypeLabel(trigger.type),
      enabled: trigger.enabled,
      runtimeStatusLabel: state?.lastStatus.name ?? 'idle',
      driftState: driftState,
      summary: _buildSummary(trigger),
      lastRunLabel: _formatDateTime(state?.lastRunAt),
      nextRunLabel: nextRun.label,
      nextRunState: nextRun.state,
      lastResultLabel: _nonEmptyOrNull(state?.lastResult) ?? 'Unavailable',
      failureLabel: _nonEmptyOrNull(state?.lastFailure) ?? 'Unavailable',
      priorityLabel: trigger.priority.name,
      lastMatchedLabel: state?.lastDecision?.name ?? 'Unavailable',
      lastAppliedLabel: _lastAppliedLabel(state),
      conditionSummary: _conditionSummary(trigger),
      actionSummary: _actionSummary(trigger),
      appliesToSummary: _appliesToSummary(trigger),
      triggerType: trigger.type,
      isStandingOrder: trigger.type == TriggerType.standingOrder,
    );
  }

  AutomationCategory _categoryFor(TriggerType type) {
    return switch (type) {
      TriggerType.schedule || TriggerType.interval || TriggerType.cron =>
        AutomationCategory.timeBased,
      TriggerType.standingOrder => AutomationCategory.standingOrders,
      _ => AutomationCategory.eventState,
    };
  }

  bool _canEdit(TriggerType type) {
    return switch (type) {
      TriggerType.schedule ||
      TriggerType.interval ||
      TriggerType.cron ||
      TriggerType.battery ||
      TriggerType.mcpEvent ||
      TriggerType.standingOrder => true,
      TriggerType.boot || TriggerType.manual => false,
    };
  }

  String _subtypeLabel(TriggerType type) {
    return switch (type) {
      TriggerType.schedule => 'At a specific time',
      TriggerType.interval => 'Repeating interval',
      TriggerType.cron => 'Advanced schedule',
      TriggerType.battery => 'When battery gets low',
      TriggerType.mcpEvent => 'Connected service event',
      TriggerType.boot => 'Boot',
      TriggerType.manual => 'Manual',
      TriggerType.standingOrder => 'Standing order',
    };
  }

  String _buildSummary(TriggerConfig trigger) {
    return switch (trigger.type) {
      TriggerType.schedule => trigger.scheduleSpec == null
          ? 'Daily schedule'
          : 'Daily at ${_two(trigger.scheduleSpec!.hour)}:${_two(trigger.scheduleSpec!.minute)}',
      TriggerType.interval => trigger.intervalSpec == null
          ? 'Repeats on an interval'
          : 'Every ${trigger.intervalSpec!.every.inMinutes} minutes',
      TriggerType.cron => 'Advanced schedule',
      TriggerType.battery => 'Runs when battery condition matches',
      TriggerType.mcpEvent => 'Runs when a connected service event arrives',
      TriggerType.boot => 'Runs when the phone starts',
      TriggerType.manual => 'Runs manually',
      TriggerType.standingOrder => 'Always applies when conditions match',
    };
  }

  ({String label, AutomationNextRunState state}) _buildNextRunLabel(
    TriggerConfig trigger,
    TriggerState? state,
  ) {
    if (trigger.type == TriggerType.schedule ||
        trigger.type == TriggerType.interval) {
      return (label: 'Unavailable', state: AutomationNextRunState.unsupported);
    }
    return (label: 'Hidden', state: AutomationNextRunState.hidden);
  }

  String _conditionSummary(TriggerConfig trigger) {
    return switch (trigger.type) {
      TriggerType.battery => trigger.batterySpec == null
          ? 'Battery condition'
          : switch (trigger.batterySpec!.condition) {
              BatteryTriggerCondition.levelAtOrBelow =>
                'Battery at or below ${trigger.batterySpec!.level ?? 20}%',
              BatteryTriggerCondition.levelAtOrAbove =>
                'Battery at or above ${trigger.batterySpec!.level ?? 20}%',
              BatteryTriggerCondition.stateChanged =>
                'Battery state changes',
            },
      TriggerType.mcpEvent => 'Connected service event',
      TriggerType.boot => 'Phone boots',
      TriggerType.manual => 'Manual trigger',
      TriggerType.standingOrder => 'Rule conditions',
      _ => 'Unavailable',
    };
  }

  String _actionSummary(TriggerConfig trigger) => _nonEmptyOrNull(trigger.prompt) ?? 'Unavailable';

  String _appliesToSummary(TriggerConfig trigger) {
    final spec = trigger.standingOrderSpec;
    if (spec == null || spec.appliesToTypes.isEmpty) {
      return 'Unavailable';
    }
    return spec.appliesToTypes.map(_subtypeLabel).join(', ');
  }

  String _lastAppliedLabel(TriggerState? state) {
    final execution = state?.lastExecution;
    if (execution == null) return 'Unavailable';
    return '${execution.status.name} @ ${_formatDateTime(execution.finishedAt)}';
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Unavailable';
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  String? _nonEmptyOrNull(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text;
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
