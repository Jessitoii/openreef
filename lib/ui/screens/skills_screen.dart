import 'package:flutter/material.dart';
import 'package:openreef/skills/skill_package_models.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/components/app_components.dart';
import 'package:openreef/ui/viewmodels/skill_viewmodels.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({required this.controller, super.key});
  final SkillRegistryController controller;

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  SkillPackageDetail? _editingPkg;

  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_editingPkg != null) {
      return _SkillEditorView(
        pkg: _editingPkg!,
        onSave: (doc) async {
          await widget.controller.saveFile(
            skillId: _editingPkg!.ref.id,
            relativePath: 'SKILL.md',
            content: doc,
          );
          if (mounted) {
            setState(() => _editingPkg = null);
          }
        },
        onCancel: () => setState(() => _editingPkg = null),
      );
    }

    return Scaffold(
      body: ValueListenableBuilder<List<SkillPackageRef>>(
        valueListenable: widget.controller.packages,
        builder: (context, packages, _) {
          return Column(
            children: [
              AppPageHeader(
                title: 'Skills',
                subtitle: 'Manage agent behaviors and capabilities.',
                actions: [
                  AppButton.primary(
                    onPressed: () async {
                      final newPkg = await widget.controller.createPackage(
                        id: 'new_skill_${DateTime.now().millisecondsSinceEpoch}',
                        markdown:
                            '---\nname: New Skill\ndescription: Describe what it does\n---\n\nWrite instructions here.\n',
                      );
                      if (mounted && newPkg != null) {
                        setState(() => _editingPkg = newPkg);
                      }
                    },
                    icon: Icons.add,
                    label: 'New Skill',
                  ),
                ],
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  itemCount: packages.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final pkg = packages[index];
                    return _SkillListTile(
                      viewModel: SkillViewModel.fromRef(pkg),
                      onEdit: () async {
                        await widget.controller.selectPackage(pkg.id);
                        final detail = widget.controller.selectedPackage.value;
                        if (detail != null && mounted) {
                          setState(() => _editingPkg = detail);
                        }
                      },
                      onToggle: (val) =>
                          widget.controller.setSkillEnabled(pkg.id, val),
                      onDelete: () => AppComponents.showDestructiveDialog(
                        context: context,
                        title: 'Delete Skill',
                        content: pkg.isWritable
                            ? 'Remove this skill package permanently?'
                            : 'Built-in skills are read-only and cannot be deleted.',
                        confirmLabel: 'Delete',
                        onConfirm: pkg.isWritable
                            ? () => widget.controller.deletePackage(pkg.id)
                            : () async {},
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

class _SkillListTile extends StatelessWidget {
  const _SkillListTile({
    required this.viewModel,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final SkillViewModel viewModel;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onEdit,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  viewModel.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(viewModel.summary, style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    AppBadge(label: viewModel.category),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'v${viewModel.version}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Switch(value: viewModel.isActive, onChanged: onToggle),
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
          Tooltip(
            message: viewModel.isBuiltIn
                ? 'Built-in skills are read-only.'
                : 'Delete skill',
            child: IconButton(
              icon: const Icon(Icons.delete_outline, color: ReefPalette.error),
              onPressed: viewModel.isBuiltIn ? null : onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillEditorView extends StatefulWidget {
  const _SkillEditorView({
    required this.pkg,
    required this.onSave,
    required this.onCancel,
  });
  final SkillPackageDetail pkg;
  final ValueChanged<String> onSave;
  final VoidCallback onCancel;

  @override
  State<_SkillEditorView> createState() => _SkillEditorViewState();
}

class _SkillEditorViewState extends State<_SkillEditorView> {
  late final TextEditingController _rawController;
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _instructionsController;
  bool _advancedMode = false;

  @override
  void initState() {
    super.initState();
    final rawInstruction = widget.pkg.rawSkillMarkdown ?? '';
    _rawController = TextEditingController(text: rawInstruction);

    final vm = SkillViewModel.fromDomain(widget.pkg);
    _nameController = TextEditingController(text: vm.name);
    _descController = TextEditingController(text: vm.summary);

    String instructions = rawInstruction;
    if (instructions.startsWith('---')) {
      final parts = instructions.split('---');
      if (parts.length >= 3) {
        instructions = parts.sublist(2).join('---').trim();
      }
    }
    _instructionsController = TextEditingController(text: instructions);
  }

  void _save() {
    if (_advancedMode) {
      widget.onSave(_rawController.text);
    } else {
      final doc =
          '---\nname: ${_nameController.text}\ndescription: ${_descController.text}\n---\n\n${_instructionsController.text}';
      widget.onSave(doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pkg.ref.id),
        actions: [
          Row(
            children: [
              const Text('Advanced'),
              Switch(
                value: _advancedMode,
                onChanged: (v) => setState(() => _advancedMode = v),
              ),
            ],
          ),
          AppButton.secondary(onPressed: widget.onCancel, label: 'Cancel'),
          const SizedBox(width: AppSpacing.sm),
          Tooltip(
            message: widget.pkg.ref.isWritable
                ? 'Save skill'
                : 'Built-in skills are read-only.',
            child: AppButton.primary(
              onPressed: widget.pkg.ref.isWritable ? _save : null,
              label: 'Save',
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: _advancedMode
          ? Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _rawController,
                maxLines: null,
                expands: true,
                style: const TextStyle(fontFamily: 'JetBrainsMono'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Raw markdown...',
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                if (!widget.pkg.ref.isWritable) ...[
                  AppCard(
                    child: Text(
                      'Built-in skills are read-only. You can review this skill, but Save and Delete are disabled.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Skill Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Short Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _instructionsController,
                  maxLines: 20,
                  decoration: const InputDecoration(
                    labelText: 'Agent Instructions (Prompt)',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
    );
  }
}
