import 'package:flutter/material.dart';
import 'package:openreef/memory/memory_record.dart';
import 'package:openreef/memory/memory_store_kind.dart';
import 'package:openreef/ui/memory_management_controller.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/components/app_components.dart';
import 'package:openreef/ui/viewmodels/memory_viewmodels.dart';

class MemoryScreen extends StatefulWidget {
  const MemoryScreen({required this.controller, super.key});
  final MemoryManagementController controller;

  @override
  State<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends State<MemoryScreen> {
  Future<void> _editRecord([MemoryRecord? record]) async {
    await AppComponents.showStandardSheet<void>(
      context: context,
      child: _MemoryEditorSheet(
        record: record,
        onSave: (next) async {
          await widget.controller.saveRecord(next, previousRecord: record);
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  Future<void> _showFilters() async {
    await AppComponents.showStandardSheet<void>(
      context: context,
      child: _MemoryFilterSheet(
        initialFilters: widget.controller.filters,
        onApply: (filters) {
          widget.controller.updateFilters(filters);
          Navigator.of(context).pop();
        },
        onReset: () {
          widget.controller.resetFilters();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  void _deleteRecord(dynamic originalRecord) {
    AppComponents.showDestructiveDialog(
      context: context,
      title: 'Forget this memory?',
      content:
          'This will permanently remove this item from the agent\'s memory.',
      confirmLabel: 'Erase',
      onConfirm: () => widget.controller.deleteRecord(originalRecord),
    );
  }

  void _clearAll() {
    AppComponents.showDestructiveDialog(
      context: context,
      title: 'Clear memory store?',
      content:
          'This will permanently delete all memory records in the current view. The agent will lose this context.',
      confirmLabel: 'Clear All',
      onConfirm: () async {
        for (final record in widget.controller.visibleRecords) {
          await widget.controller.deleteRecord(record);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final count = widget.controller.visibleRecords.length;
          final viewModels = widget.controller.visibleRecords
              .map((r) => MemoryViewModel.fromDomain(r))
              .toList();

          return Column(
            children: [
              AppPageHeader(
                title: 'Memory Bank',
                subtitle: 'Review and manage what the agent remembers.',
                actions: [
                  AppButton.secondary(
                    onPressed: widget.controller.isMutating
                        ? null
                        : _showFilters,
                    icon: Icons.filter_list,
                    label: 'Filters',
                  ),
                  AppButton.primary(
                    onPressed: widget.controller.isMutating
                        ? null
                        : () => _editRecord(),
                    icon: Icons.add,
                    label: 'Add Memory',
                  ),
                  if (count > 0)
                    AppButton.destructive(
                      onPressed: widget.controller.isMutating
                          ? null
                          : _clearAll,
                      icon: Icons.delete_sweep,
                      label: 'Erase All',
                    ),
                ],
              ),
              Expanded(
                child: count == 0
                    ? const StateView.empty(
                        title: 'No memories found',
                        subtitle: 'The agent has a clean slate right now.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        itemCount: viewModels.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          return _MemoryEntryCard(
                            viewModel: viewModels[index],
                            onEdit: () => _editRecord(
                              widget.controller.visibleRecords[index],
                            ),
                            onDelete: () => _deleteRecord(
                              widget.controller.visibleRecords[index],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MemoryEntryCard extends StatelessWidget {
  const _MemoryEntryCard({
    required this.viewModel,
    required this.onEdit,
    required this.onDelete,
  });

  final MemoryViewModel viewModel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(label: viewModel.storeLabel),
              const SizedBox(width: AppSpacing.sm),
              AppBadge(label: viewModel.categoryLabel),
              const Spacer(),
              Text(viewModel.createdLabel, style: theme.textTheme.bodySmall),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
                tooltip: 'Edit memory',
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: ReefPalette.error,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(viewModel.content, style: theme.textTheme.bodyMedium),
          if (viewModel.detailsMap.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ExpansionTile(
              title: const Text('Metadata'),
              tilePadding: EdgeInsets.zero,
              children: viewModel.detailsMap.entries
                  .map(
                    (e) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(
                              e.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(child: Text(e.value)),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MemoryEditorSheet extends StatefulWidget {
  const _MemoryEditorSheet({required this.record, required this.onSave});

  final MemoryRecord? record;
  final Future<void> Function(MemoryRecord record) onSave;

  @override
  State<_MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<_MemoryEditorSheet> {
  late final TextEditingController _contentController;
  late final TextEditingController _categoryController;
  late final TextEditingController _importanceController;
  late final TextEditingController _metadataController;
  late _MemoryType _type;
  bool _advanced = false;
  bool _saving = false;
  String? _contentError;
  String? _importanceError;
  String? _metadataError;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _type = _MemoryType.fromStore(record?.store ?? MemoryStoreKind.longTerm);
    _contentController = TextEditingController(text: record?.content ?? '');
    _categoryController = TextEditingController(
      text: record?.category.isNotEmpty == true ? record!.category : 'General',
    );
    _importanceController = TextEditingController(
      text: (record?.importance.clamp(1, 5) ?? 3).toString(),
    );
    _metadataController = TextEditingController(
      text: _metadataToText(record?.metadata ?? const <String, Object?>{}),
    );
  }

  @override
  void dispose() {
    _contentController.dispose();
    _categoryController.dispose();
    _importanceController.dispose();
    _metadataController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    final importance = int.tryParse(_importanceController.text.trim());
    final metadata = _parseMetadata(_metadataController.text);
    setState(() {
      _contentError = content.isEmpty
          ? 'Write what OpenReef should remember.'
          : null;
      _importanceError = importance == null || importance < 1 || importance > 5
          ? 'Use a value from 1 to 5.'
          : null;
      _metadataError = metadata == null
          ? 'Use one key=value pair per line.'
          : null;
    });
    if (_contentError != null ||
        _importanceError != null ||
        _metadataError != null ||
        importance == null ||
        metadata == null) {
      return;
    }
    setState(() => _saving = true);
    final previous = widget.record;
    final now = DateTime.now().toUtc();
    final record = MemoryRecord(
      id: previous?.id,
      store: _type.store,
      key: previous?.key ?? 'manual_memory_${now.microsecondsSinceEpoch}',
      content: content,
      category: _categoryController.text.trim().isEmpty
          ? 'General'
          : _categoryController.text.trim(),
      importance: importance,
      createdAt: previous?.createdAt ?? now,
      expiresAt: previous?.expiresAt,
      metadata: metadata,
    );
    try {
      await widget.onSave(record);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.record == null ? 'Add Memory' : 'Edit Memory',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _contentController,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Memory',
              errorText: _contentError,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<_MemoryType>(
            initialValue: _type,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Type',
            ),
            items: _MemoryType.values
                .map(
                  (type) =>
                      DropdownMenuItem(value: type, child: Text(type.label)),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (type) {
                    if (type != null) setState(() => _type = type);
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _categoryController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Category',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _importanceController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: 'Importance (1-5)',
              errorText: _importanceError,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Advanced metadata'),
            subtitle: const Text('Optional key=value lines'),
            value: _advanced,
            onChanged: (value) => setState(() => _advanced = value),
          ),
          if (_advanced)
            TextField(
              controller: _metadataController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Metadata',
                errorText: _metadataError,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton.primary(
              onPressed: _saving ? null : _save,
              label: _saving ? 'Saving...' : 'Save Memory',
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  static String _metadataToText(Map<String, Object?> metadata) {
    return metadata.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('\n');
  }

  static Map<String, Object?>? _parseMetadata(String text) {
    final metadata = <String, Object?>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final index = trimmed.indexOf('=');
      if (index <= 0) {
        return null;
      }
      metadata[trimmed.substring(0, index).trim()] = trimmed
          .substring(index + 1)
          .trim();
    }
    return metadata;
  }
}

class _MemoryFilterSheet extends StatefulWidget {
  const _MemoryFilterSheet({
    required this.initialFilters,
    required this.onApply,
    required this.onReset,
  });

  final MemoryFilterState initialFilters;
  final ValueChanged<MemoryFilterState> onApply;
  final VoidCallback onReset;

  @override
  State<_MemoryFilterSheet> createState() => _MemoryFilterSheetState();
}

class _MemoryFilterSheetState extends State<_MemoryFilterSheet> {
  late final TextEditingController _searchController;
  late final TextEditingController _categoryController;
  late _MemoryType? _type;
  late bool _showExpired;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: widget.initialFilters.search,
    );
    _categoryController = TextEditingController(
      text: widget.initialFilters.category,
    );
    _type = widget.initialFilters.store == null
        ? null
        : _MemoryType.fromStore(widget.initialFilters.store!);
    _showExpired = widget.initialFilters.showExpired;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Filters', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Search',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _categoryController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Category',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<_MemoryType?>(
          initialValue: _type,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Type',
          ),
          items: <DropdownMenuItem<_MemoryType?>>[
            const DropdownMenuItem(value: null, child: Text('All types')),
            ..._MemoryType.values.map(
              (type) => DropdownMenuItem(value: type, child: Text(type.label)),
            ),
          ],
          onChanged: (type) => setState(() => _type = type),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Show expired memories'),
          value: _showExpired,
          onChanged: (value) => setState(() => _showExpired = value),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            AppButton.secondary(onPressed: widget.onReset, label: 'Reset'),
            AppButton.primary(
              onPressed: () => widget.onApply(
                MemoryFilterState(
                  store: _type?.store,
                  category: _categoryController.text.trim(),
                  showExpired: _showExpired,
                  search: _searchController.text.trim(),
                ),
              ),
              label: 'Apply',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

class _MemoryType {
  const _MemoryType(this.label, this.store);

  static const values = <_MemoryType>[
    _MemoryType('Learned memory', MemoryStoreKind.longTerm),
    _MemoryType('Temporary context', MemoryStoreKind.shortTerm),
    _MemoryType('History', MemoryStoreKind.episodic),
    _MemoryType('Internal state', MemoryStoreKind.skillState),
    _MemoryType('Connection data', MemoryStoreKind.mcpConnections),
  ];

  final String label;
  final MemoryStoreKind store;

  static _MemoryType fromStore(MemoryStoreKind store) {
    for (final type in values) {
      if (type.store == store) {
        return type;
      }
    }
    return values.first;
  }
}
