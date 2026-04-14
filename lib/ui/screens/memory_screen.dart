import 'package:flutter/material.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/ui/memory_management_controller.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({required this.controller, super.key});

  final MemoryManagementController controller;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _metadataController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryController.dispose();
    _metadataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, child) {
        final controller = widget.controller;
        final records = controller.visibleRecords;
        final filteredRecords = controller.filteredRecords;
        final selected = controller.selectedRecord;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(controller: controller),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Search memories',
                  hintText: 'Search content, key, category, or metadata',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: controller.filters.search.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            controller.updateFilters(
                              controller.filters.copyWith(search: ''),
                            );
                          },
                          icon: const Icon(Icons.clear),
                        ),
                ),
                onChanged: (value) {
                  controller.updateFilters(
                    controller.filters.copyWith(search: value),
                  );
                },
              ),
              const SizedBox(height: 8),
              _QuickFilters(
                controller: controller,
                categoryController: _categoryController,
                onResetFilters: () {
                  _searchController.clear();
                  _categoryController.clear();
                  _metadataController.clear();
                  controller.resetFilters();
                },
                onAdvancedFilters: () {
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (context) => _AdvancedFiltersSheet(
                      controller: controller,
                      metadataController: _metadataController,
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _BulkActionsBar(
                count: filteredRecords.length,
                byStore: _countByStore(filteredRecords),
                onDeleteFiltered: filteredRecords.isEmpty || controller.isMutating
                    ? null
                    : () => _confirmBulkDelete(
                        context,
                        controller,
                        filteredRecords,
                      ),
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: 10),
                _ErrorBanner(message: controller.errorMessage!),
              ],
              if (controller.warningMessage != null) ...[
                const SizedBox(height: 10),
                _WarningBanner(message: controller.warningMessage!),
              ],
              const SizedBox(height: 10),
              Expanded(
                child: controller.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : records.isEmpty
                        ? _EmptyState(hasFilters: _hasFilters(controller.filters))
                        : ListView.builder(
                            itemCount: records.length + (selected == null ? 0 : 1),
                            itemBuilder: (context, index) {
                              if (index >= records.length) {
                                if (!controller.hasMoreThanVisibleLimit) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: _DetailCard(
                                      record: selected!,
                                      onEdit: () => _openEditor(
                                        context,
                                        controller: controller,
                                        record: selected,
                                      ),
                                    ),
                                  );
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    'Showing ${records.length} of ${filteredRecords.length} memories',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                );
                              }
                              final record = records[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _MemoryTile(
                                  record: record,
                                  selected: selected?.key == record.key,
                                  onTap: () => controller.selectRecord(record.key),
                                  onEdit: () => _openEditor(
                                    context,
                                    controller: controller,
                                    record: record,
                                  ),
                                  onDelete: () => _confirmDelete(
                                    context,
                                    controller,
                                    record,
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _hasFilters(MemoryFilterState filters) {
    return filters.search.trim().isNotEmpty ||
        filters.category.trim().isNotEmpty ||
        filters.metadataText.trim().isNotEmpty ||
        filters.store != null ||
        !filters.showExpired;
  }

  Map<MemoryStoreKind, int> _countByStore(List<MemoryRecord> records) {
    final counts = <MemoryStoreKind, int>{};
    for (final record in records) {
      counts[record.store] = (counts[record.store] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _openEditor(
    BuildContext context, {
    required MemoryManagementController controller,
    MemoryRecord? record,
  }) async {
    final result = await showModalBottomSheet<MemoryRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MemoryEditorSheet(record: record),
    );
    if (result == null) return;
    await controller.saveRecord(result, previousRecord: record);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    MemoryManagementController controller,
    MemoryRecord record,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete memory?'),
        content: Text(
          'Delete ${record.key} from ${_storeLabel(record.store)}? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteRecord(record);
    }
  }

  Future<void> _confirmBulkDelete(
    BuildContext context,
    MemoryManagementController controller,
    List<MemoryRecord> records,
  ) async {
    final breakdown = _countByStore(records);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete filtered memories?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are about to delete ${records.length} memories:'),
            const SizedBox(height: 10),
            for (final entry in breakdown.entries)
              Text('• ${entry.value} ${_storeLabel(entry.key)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete Filtered'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await controller.bulkDelete(
      store: controller.filters.store,
      category: controller.filters.category.trim().isEmpty
          ? null
          : controller.filters.category.trim(),
      includeExpired: controller.filters.showExpired,
    );
  }

  String _storeLabel(MemoryStoreKind store) {
    return switch (store) {
      MemoryStoreKind.shortTerm => 'temporary',
      MemoryStoreKind.longTerm => 'semantic',
      MemoryStoreKind.episodic => 'history',
      MemoryStoreKind.skillState => 'internal',
      MemoryStoreKind.mcpConnections => 'mcp_connections',
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final MemoryManagementController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Memory',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Real stored memory records with truthful controls.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            Chip(label: Text('${controller.visibleRecords.length} visible')),
            Chip(label: Text('${controller.allRecords.length} total')),
          ],
        ),
      ],
    );
  }
}

class _QuickFilters extends StatelessWidget {
  const _QuickFilters({
    required this.controller,
    required this.categoryController,
    required this.onResetFilters,
    required this.onAdvancedFilters,
  });

  final MemoryManagementController controller;
  final TextEditingController categoryController;
  final VoidCallback onResetFilters;
  final VoidCallback onAdvancedFilters;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<MemoryStoreKind?>(
          value: controller.filters.store,
          hint: const Text('Store'),
          items: const [
            DropdownMenuItem(value: null, child: Text('All stores')),
            DropdownMenuItem(value: MemoryStoreKind.shortTerm, child: Text('temporary')),
            DropdownMenuItem(value: MemoryStoreKind.longTerm, child: Text('semantic')),
            DropdownMenuItem(value: MemoryStoreKind.episodic, child: Text('history')),
            DropdownMenuItem(value: MemoryStoreKind.skillState, child: Text('internal')),
          ],
          onChanged: (value) {
            controller.updateFilters(
              controller.filters.copyWith(clearStore: value == null, store: value),
            );
          },
        ),
        SizedBox(
          width: 160,
          child: TextField(
            controller: categoryController,
            decoration: const InputDecoration(
              labelText: 'Category',
              isDense: true,
            ),
            onChanged: (value) {
              controller.updateFilters(
                controller.filters.copyWith(category: value),
              );
            },
          ),
        ),
        FilterChip(
          label: const Text('Show expired'),
          selected: controller.filters.showExpired,
          onSelected: (value) {
            controller.updateFilters(
              controller.filters.copyWith(showExpired: value),
            );
          },
        ),
        TextButton.icon(
          onPressed: onAdvancedFilters,
          icon: const Icon(Icons.tune),
          label: const Text('Advanced'),
        ),
        TextButton(
          onPressed: onResetFilters,
          child: const Text('Reset Filters'),
        ),
      ],
    );
  }
}

class _BulkActionsBar extends StatelessWidget {
  const _BulkActionsBar({
    required this.count,
    required this.byStore,
    required this.onDeleteFiltered,
  });

  final int count;
  final Map<MemoryStoreKind, int> byStore;
  final VoidCallback? onDeleteFiltered;

  @override
  Widget build(BuildContext context) {
    final parts = byStore.entries
        .map(
          (entry) =>
              '${entry.value} ${switch (entry.key) { MemoryStoreKind.shortTerm => 'temporary', MemoryStoreKind.longTerm => 'semantic', MemoryStoreKind.episodic => 'history', MemoryStoreKind.skillState => 'internal', MemoryStoreKind.mcpConnections => 'mcp_connections' }}',
        )
        .toList(growable: false);
    return Row(
      children: [
        Expanded(
          child: Text(
            parts.isEmpty
                ? 'Filtered results: $count'
                : 'Filtered results: $count | ${parts.join(' | ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        TextButton.icon(
          onPressed: onDeleteFiltered,
          icon: Icon(
            Icons.delete_forever_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
          label: Text(
            'Delete Filtered',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.record,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final MemoryRecord record;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        selected: selected,
        onTap: onTap,
        title: Text(
          record.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _StoreBadge(store: record.store),
                  if (record.category.isNotEmpty) _MiniChip(label: record.category),
                  _ImportancePip(value: record.importance),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Created ${_formatDate(record.createdAt)}${record.expiresAt == null ? '' : ' · Expires ${_formatDate(record.expiresAt!)}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit memory',
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              tooltip: 'Delete memory',
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreBadge extends StatelessWidget {
  const _StoreBadge({required this.store});

  final MemoryStoreKind store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, icon, color, bgAlpha, borderAlpha) = switch (store) {
      MemoryStoreKind.shortTerm => ('temporary', Icons.schedule, theme.colorScheme.onSurfaceVariant, 0.08, 0.25),
      MemoryStoreKind.longTerm => ('semantic', Icons.auto_awesome, theme.colorScheme.primary, 0.12, 0.45),
      MemoryStoreKind.episodic => ('history', Icons.history, theme.colorScheme.onSurfaceVariant, 0.08, 0.25),
      MemoryStoreKind.skillState => ('internal', Icons.lock_outline, theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72), 0.06, 0.18),
      MemoryStoreKind.mcpConnections => ('mcp_connections', Icons.link, theme.colorScheme.onSurfaceVariant, 0.08, 0.25),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: borderAlpha)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _ImportancePip extends StatelessWidget {
  const _ImportancePip({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final active = value.clamp(1, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final filled = index < active;
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Icon(
            filled ? Icons.circle : Icons.circle_outlined,
            size: 9,
            color: filled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
        );
      }),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.record, required this.onEdit});

  final MemoryRecord record;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final metadataEntries = record.metadata.entries.toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: Text('Selected Memory')),
                TextButton(onPressed: onEdit, child: const Text('Edit')),
              ],
            ),
            const SizedBox(height: 8),
            _Row(label: 'Content', value: record.content),
            _Row(label: 'Store', value: record.store.value),
            _Row(label: 'Category', value: record.category),
            _Row(label: 'Importance', value: '${record.importance}'),
            _Row(label: 'Created', value: _formatDate(record.createdAt)),
            _Row(
              label: 'Expires',
              value: record.expiresAt == null
                  ? 'unavailable'
                  : _formatDate(record.expiresAt!),
            ),
            const SizedBox(height: 10),
            const Text('Metadata'),
            const SizedBox(height: 6),
            if (metadataEntries.isEmpty)
              const Text('unavailable')
            else
              ...metadataEntries.map(
                (entry) => _Row(label: entry.key, value: entry.value.toString()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters});

  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storage_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              hasFilters ? 'No memories match the current filters' : 'No memories found',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Memories are created automatically from conversations or can be added manually.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(message),
      ),
    );
  }
}

class _MemoryEditorSheet extends StatefulWidget {
  const _MemoryEditorSheet({this.record});

  final MemoryRecord? record;

  @override
  State<_MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<_MemoryEditorSheet> {
  late final TextEditingController _keyController;
  late final TextEditingController _contentController;
  late final TextEditingController _categoryController;
  late final TextEditingController _importanceController;
  late final TextEditingController _expiresController;
  late final TextEditingController _metadataController;
  late MemoryStoreKind _store;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _keyController = TextEditingController(text: record?.key ?? '');
    _contentController = TextEditingController(text: record?.content ?? '');
    _categoryController = TextEditingController(text: record?.category ?? '');
    _importanceController =
        TextEditingController(text: record?.importance.toString() ?? '1');
    _expiresController =
        TextEditingController(text: record?.expiresAt?.toIso8601String() ?? '');
    _metadataController = TextEditingController(
      text: record?.metadata.entries.map((e) => '${e.key}=${e.value}').join('\n') ?? '',
    );
    _store = record?.store ?? MemoryStoreKind.shortTerm;
  }

  @override
  void dispose() {
    _keyController.dispose();
    _contentController.dispose();
    _categoryController.dispose();
    _importanceController.dispose();
    _expiresController.dispose();
    _metadataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      record == null ? 'New Memory' : 'Edit Memory',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (record?.store == MemoryStoreKind.longTerm)
                    const _WarningBanner(
                      message:
                          'Editing semantic memory may affect retrieval behavior',
                    ),
                  if (record?.store == MemoryStoreKind.skillState)
                    const _WarningBanner(
                      message:
                          'Internal memory used by skills. Modify with caution.',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const _FormFieldLabel(label: 'Key *', optional: false),
              TextField(
                controller: _keyController,
                enabled: record == null,
                decoration: const InputDecoration(
                  hintText: 'Unique memory key',
                ),
              ),
              const SizedBox(height: 12),
              _StoreField(
                value: _store,
                enabled: record == null,
                onChanged: (value) => setState(() => _store = value),
              ),
              const SizedBox(height: 12),
              const _FormFieldLabel(label: 'Category *', optional: false),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  hintText: 'Category or grouping label',
                ),
              ),
              const SizedBox(height: 12),
              const _FormFieldLabel(label: 'Content *', optional: false),
              TextField(
                controller: _contentController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Memory text',
                ),
              ),
              const SizedBox(height: 12),
              const _FormFieldLabel(label: 'Importance *', optional: false),
              TextField(
                controller: _importanceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: '1-5',
                ),
              ),
              const SizedBox(height: 12),
              const _FormFieldLabel(label: 'Expires at', optional: true),
              TextField(
                controller: _expiresController,
                decoration: const InputDecoration(
                  hintText: 'Optional ISO8601 timestamp',
                ),
              ),
              const SizedBox(height: 12),
              const _FormFieldLabel(label: 'Metadata', optional: true),
              TextField(
                controller: _metadataController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Optional key=value per line',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final key = _keyController.text.trim();
    final content = _contentController.text.trim();
    final category = _categoryController.text.trim();
    final importance = int.tryParse(_importanceController.text.trim()) ?? 1;
    final expiresAt = _expiresController.text.trim().isEmpty
        ? null
        : DateTime.tryParse(_expiresController.text.trim());
    final metadata = <String, Object?>{};
    for (final line in _metadataController.text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || !trimmed.contains('=')) continue;
      final parts = trimmed.split('=');
      metadata[parts.first.trim()] = parts.skip(1).join('=').trim();
    }
    if (key.isEmpty || content.isEmpty || category.isEmpty) return;
    Navigator.pop(
      context,
      MemoryRecord(
        id: widget.record?.id,
        store: widget.record?.store ?? _store,
        key: key,
        content: content,
        category: category,
        importance: importance.clamp(1, 5),
        createdAt: widget.record?.createdAt ?? DateTime.now().toUtc(),
        expiresAt: expiresAt,
        metadata: metadata,
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _FormFieldLabel extends StatelessWidget {
  const _FormFieldLabel({required this.label, required this.optional});

  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        optional ? '$label (optional)' : label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _StoreField extends StatelessWidget {
  const _StoreField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final MemoryStoreKind value;
  final bool enabled;
  final ValueChanged<MemoryStoreKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<MemoryStoreKind>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Store *'),
      items: const [
        DropdownMenuItem(value: MemoryStoreKind.shortTerm, child: Text('temporary')),
        DropdownMenuItem(value: MemoryStoreKind.longTerm, child: Text('semantic')),
        DropdownMenuItem(value: MemoryStoreKind.episodic, child: Text('history')),
        DropdownMenuItem(value: MemoryStoreKind.skillState, child: Text('internal')),
      ],
      onChanged: enabled ? (value) { if (value != null) onChanged(value); } : null,
    );
  }
}

class _AdvancedFiltersSheet extends StatelessWidget {
  const _AdvancedFiltersSheet({
    required this.controller,
    required this.metadataController,
  });

  final MemoryManagementController controller;
  final TextEditingController metadataController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Advanced Filters',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: metadataController,
            decoration: const InputDecoration(
              labelText: 'Metadata text match (simple)',
              helperText:
                  'Performs simple text matching on metadata. Not structured filtering.',
            ),
            onChanged: (value) {
              controller.updateFilters(
                controller.filters.copyWith(metadataText: value),
              );
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
