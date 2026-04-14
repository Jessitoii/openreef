import 'package:flutter/material.dart';
import 'package:openreef/triggers/trigger_models.dart';
import 'package:openreef/ui/automation_builder_screen.dart';
import 'package:openreef/ui/automation_controller.dart';
import 'package:openreef/ui/automation_models.dart';

class AutomationScreen extends StatefulWidget {
  const AutomationScreen({required this.controller, super.key});

  final AutomationController controller;

  @override
  State<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends State<AutomationScreen> {
  final TextEditingController _searchController = TextEditingController();
  AutomationTab _tab = AutomationTab.timeBased;

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        final items = _filteredItems(controller);
        return RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _HeaderCard(
                enabledCount: controller.enabledCount,
                disabledCount: controller.disabledCount,
                totalCount: controller.allItems.length,
                refreshState: controller.isRefreshing
                    ? 'Refreshing...'
                    : controller.errorMessage ?? 'Runtime ready',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  labelText: 'Search automations',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tab in AutomationTab.values)
                    FilterChip(
                      label: Text(tab.label),
                      selected: _tab == tab,
                      onSelected: (_) => setState(() => _tab = tab),
                    ),
                ],
              ),
              if (controller.isLoading) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ] else if (controller.errorMessage != null) ...[
                const SizedBox(height: 16),
                _ErrorState(message: controller.errorMessage!),
              ] else if (items.isEmpty) ...[
                const SizedBox(height: 16),
                const _EmptyState(),
              ] else ...[
                const SizedBox(height: 16),
                ...items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AutomationCard(
                      item: item,
                      onToggleEnabled: item.canEdit
                          ? () => widget.controller.setEnabled(
                              item.id,
                              !item.enabled,
                            )
                          : null,
                      onDelete: item.canDelete
                          ? () => _confirmDelete(context, item)
                          : null,
                      onTap: item.canEdit || item.driftState == AutomationDriftState.persistedNotRegistered
                          ? () => _openDetail(context, item.id)
                          : () => _openDetail(context, item.id),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _createAutomation(context),
                icon: const Icon(Icons.add),
                label: const Text('Create automation'),
              ),
            ],
          ),
        );
      },
    );
  }

  List<AutomationListItemViewModel> _filteredItems(AutomationController controller) {
    final query = _searchController.text.trim().toLowerCase();
    final source = switch (_tab) {
      AutomationTab.timeBased => controller.timeBasedItems,
      AutomationTab.eventState => controller.eventStateItems,
      AutomationTab.standingOrders => controller.standingOrderItems,
    };
    if (query.isEmpty) return source;
    return source.where((item) {
      return item.title.toLowerCase().contains(query) ||
          item.summary.toLowerCase().contains(query) ||
          item.runtimeStatusLabel.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AutomationListItemViewModel item,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete automation?'),
        content: Text('Delete "${item.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      await widget.controller.deleteTrigger(item.id);
    }
  }

  Future<void> _createAutomation(BuildContext context) async {
    final draft = await Navigator.of(context).push<AutomationEditorDraft>(
      MaterialPageRoute(
        builder: (context) => AutomationBuilderScreen(
          controller: widget.controller,
          initialDraft: AutomationBuilderCatalog.defaultDraft(),
        ),
      ),
    );
    if (draft != null) {
      await widget.controller.saveFromDraft(draft);
    }
  }

  Future<void> _openDetail(BuildContext context, String id) async {
    final detail = widget.controller.detailFor(id);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AutomationDetailSheet(
        detail: detail,
        controller: widget.controller,
      ),
    );
  }
}

enum AutomationTab { timeBased, eventState, standingOrders }

extension on AutomationTab {
  String get label => switch (this) {
        AutomationTab.timeBased => 'Time-based',
        AutomationTab.eventState => 'Event / State',
        AutomationTab.standingOrders => 'Standing Orders',
      };
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.enabledCount,
    required this.disabledCount,
    required this.totalCount,
    required this.refreshState,
  });

  final int enabledCount;
  final int disabledCount;
  final int totalCount;
  final String refreshState;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(label: '$totalCount total'),
            _Chip(label: '$enabledCount enabled'),
            _Chip(label: '$disabledCount disabled'),
            _Chip(label: refreshState),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Chip(label: Text(label));
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({
    required this.item,
    required this.onToggleEnabled,
    required this.onDelete,
    required this.onTap,
  });

  final AutomationListItemViewModel item;
  final VoidCallback? onToggleEnabled;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(item.summary),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Badge(label: item.enabled ? 'Enabled' : 'Disabled'),
                _Badge(label: item.runtimeStatusLabel),
                if (item.driftState == AutomationDriftState.persistedNotRegistered)
                  const _Badge(label: 'persisted_not_registered'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton(
                  onPressed: onToggleEnabled,
                  child: Text(item.enabled ? 'Disable' : 'Enable'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onTap,
                  child: const Text('Open'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onDelete,
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _AutomationDetailSheet extends StatelessWidget {
  const _AutomationDetailSheet({
    required this.detail,
    required this.controller,
  });

  final AutomationDetailViewModel detail;
  final AutomationController controller;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (detail.lastRunLabel != 'Unavailable')
        _DetailRow(label: 'Last run', value: detail.lastRunLabel),
      if (detail.nextRunState == AutomationNextRunState.available)
        _DetailRow(label: 'Next run', value: detail.nextRunLabel),
      if (detail.lastResultLabel != 'Unavailable')
        _DetailRow(label: 'Last result', value: detail.lastResultLabel),
      if (detail.failureLabel != 'Unavailable')
        _DetailRow(label: 'Failure', value: detail.failureLabel),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(label: Text(detail.subtypeLabel)),
                Chip(label: Text(detail.runtimeStatusLabel)),
                if (detail.driftState == AutomationDriftState.persistedNotRegistered)
                  const Chip(label: Text('persisted_not_registered')),
              ],
            ),
            const SizedBox(height: 12),
            for (final row in rows) row,
            const SizedBox(height: 12),
            if (detail.isStandingOrder) ...[
              _DetailRow(label: 'Priority', value: detail.priorityLabel),
              _DetailRow(label: 'Condition', value: detail.conditionSummary),
              _DetailRow(label: 'Action', value: detail.actionSummary),
              _DetailRow(label: 'Applies to', value: detail.appliesToSummary),
              _DetailRow(label: 'Last matched', value: detail.lastMatchedLabel),
              _DetailRow(label: 'Last applied', value: detail.lastAppliedLabel),
            ],
            if (detail.runtimeStatusLabel.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (detail.triggerType != TriggerType.boot &&
                      detail.triggerType != TriggerType.manual &&
                      detail.triggerType != TriggerType.standingOrder)
                    OutlinedButton(
                      onPressed: () async {
                        final draft = controller.draftForEdit(detail.id);
                        final next = await Navigator.of(context).push<AutomationEditorDraft>(
                          MaterialPageRoute(
                            builder: (context) => AutomationBuilderScreen(
                              controller: controller,
                              initialDraft: draft,
                            ),
                          ),
                        );
                        if (next != null) {
                          await controller.saveFromDraft(next);
                        }
                      },
                      child: const Text('Edit'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No automations found.')));
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Unable to load automations: $message')));
  }
}
