import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openreef/skills/skill.dart';
import 'package:openreef/skills/skill_package_models.dart';
import 'package:openreef/skills/skill_registry_controller.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({
    required this.controller,
    super.key,
  });

  final SkillRegistryController controller;

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  static const double _mobileBreakpoint = 720;
  static const double _desktopBreakpoint = 1080;

  String? _selectedFilePath;
  bool _dirty = false;
  bool _mobileDetailMode = false;
  final TextEditingController _editorController = TextEditingController();
  final TextEditingController _createController = TextEditingController();

  @override
  void dispose() {
    _editorController.dispose();
    _createController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller.packages,
        widget.controller.selectedPackage,
      ]),
      builder: (context, _) {
        final packages = widget.controller.packages.value;
        final activePackage = widget.controller.selectedPackage.value;
        final isWide = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
        final isMedium = MediaQuery.sizeOf(context).width >= _mobileBreakpoint;

        if (activePackage != null && _selectedFilePath == null) {
          _selectedFilePath = _initialFileFor(activePackage);
          _syncEditor(activePackage);
        }

        if (!isMedium) {
          return _buildMobileFlow(context, packages, activePackage);
        }

        if (isWide) {
          return _buildSplitView(
            context,
            packages: packages,
            activePackage: activePackage,
          );
        }

        return _buildStackedTabletView(
          context,
          packages: packages,
          activePackage: activePackage,
        );
      },
    );
  }

  Widget _buildMobileFlow(
    BuildContext context,
    List<SkillPackageRef> packages,
    SkillPackageDetail? activePackage,
  ) {
    if (_mobileDetailMode && activePackage != null) {
      return Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _MobileHeader(
                  title: 'Skills',
                  onRefresh: widget.controller.reload,
                  onCreate: _showCreateDialog,
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _mobileDetailMode = false;
                        });
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to skills'),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _SkillDetailView(
                  package: activePackage,
                  selectedFilePath: _selectedFilePath,
                  editorController: _editorController,
                  dirty: _dirty,
                  mobileMode: true,
                  onPickFile: (path) {
                    setState(() {
                      _selectedFilePath = path;
                      _dirty = false;
                    });
                    unawaited(_loadEditorContent(activePackage, path));
                  },
                  onEditorChanged: () => setState(() => _dirty = true),
                  onSave: () async => _saveActivePackage(activePackage),
                  onToggleEnabled: () async {
                    await widget.controller.setSkillEnabled(
                      activePackage.ref.id,
                      !activePackage.ref.isEnabled,
                    );
                  },
                  onDelete: activePackage.ref.isWritable
                      ? () async => _deleteActivePackage(activePackage)
                      : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _MobileHeader(
              title: 'Skills',
              onRefresh: widget.controller.reload,
              onCreate: _showCreateDialog,
            ),
            Expanded(
              child: _SkillsListPane(
                packages: packages,
                selectedId: activePackage?.ref.id,
                onRefresh: widget.controller.reload,
                onCreate: _showCreateDialog,
                onSelect: (skillId) async {
                  await widget.controller.selectPackage(skillId);
                  setState(() {
                    _selectedFilePath = null;
                    _dirty = false;
                    _mobileDetailMode = true;
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStackedTabletView(
    BuildContext context, {
    required List<SkillPackageRef> packages,
    required SkillPackageDetail? activePackage,
  }) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 320,
              child: _SkillsListPane(
                packages: packages,
                selectedId: activePackage?.ref.id,
                onRefresh: widget.controller.reload,
                onCreate: _showCreateDialog,
                onSelect: (skillId) async {
                  await widget.controller.selectPackage(skillId);
                  setState(() {
                    _selectedFilePath = null;
                    _dirty = false;
                  });
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: activePackage == null
                  ? const Center(
                      child: Text('Select a skill package to inspect files.'),
                    )
                  : _SkillDetailView(
                      package: activePackage,
                      selectedFilePath: _selectedFilePath,
                      editorController: _editorController,
                      dirty: _dirty,
                      mobileMode: false,
                      onPickFile: (path) {
                        setState(() {
                          _selectedFilePath = path;
                          _dirty = false;
                        });
                        unawaited(_loadEditorContent(activePackage, path));
                      },
                      onEditorChanged: () => setState(() => _dirty = true),
                      onSave: () => _saveActivePackage(activePackage),
                      onToggleEnabled: () async {
                        await widget.controller.setSkillEnabled(
                          activePackage.ref.id,
                          !activePackage.ref.isEnabled,
                        );
                      },
                      onDelete: activePackage.ref.isWritable
                          ? () async => _deleteActivePackage(activePackage)
                          : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSplitView(
    BuildContext context, {
    required List<SkillPackageRef> packages,
    required SkillPackageDetail? activePackage,
  }) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 360,
              child: _SkillsListPane(
                packages: packages,
                selectedId: activePackage?.ref.id,
                onRefresh: widget.controller.reload,
                onCreate: _showCreateDialog,
                onSelect: (skillId) async {
                  await widget.controller.selectPackage(skillId);
                  setState(() {
                    _selectedFilePath = null;
                    _dirty = false;
                  });
                },
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: activePackage == null
                  ? const Center(
                      child: Text('Select a skill package to inspect files.'),
                    )
                  : _SkillDetailView(
                      package: activePackage,
                      selectedFilePath: _selectedFilePath,
                      editorController: _editorController,
                      dirty: _dirty,
                      mobileMode: false,
                      onPickFile: (path) {
                        setState(() {
                          _selectedFilePath = path;
                          _dirty = false;
                        });
                        unawaited(_loadEditorContent(activePackage, path));
                      },
                      onEditorChanged: () => setState(() => _dirty = true),
                      onSave: () => _saveActivePackage(activePackage),
                      onToggleEnabled: () async {
                        await widget.controller.setSkillEnabled(
                          activePackage.ref.id,
                          !activePackage.ref.isEnabled,
                        );
                      },
                      onDelete: activePackage.ref.isWritable
                          ? () async => _deleteActivePackage(activePackage)
                          : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveActivePackage(SkillPackageDetail package) async {
    final filePath = _selectedFilePath;
    if (filePath == null || !package.ref.isWritable) {
      return;
    }
    final updated = await widget.controller.saveFile(
      skillId: package.ref.id,
      relativePath: filePath,
      content: _editorController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _dirty = false;
      if (updated != null) {
        _syncEditor(updated);
      }
    });
  }

  Future<void> _deleteActivePackage(SkillPackageDetail package) async {
    final confirmed = await _confirmDelete(context);
    if (!confirmed) {
      return;
    }
    await widget.controller.deletePackage(package.ref.id);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedFilePath = null;
      _dirty = false;
      _editorController.clear();
      _mobileDetailMode = false;
    });
  }

  String? _initialFileFor(SkillPackageDetail detail) {
    final textNode = detail.fileTree
        .where((n) => n.kind == SkillFileKind.text)
        .cast<SkillFileNode?>()
        .firstWhere((n) => n != null, orElse: () => null);
    return textNode?.relativePath ??
        (detail.fileTree.isNotEmpty ? detail.fileTree.first.relativePath : null);
  }

  void _syncEditor(SkillPackageDetail detail) {
    final selectedFile = _selectedFilePath;
    if (selectedFile == null) {
      _editorController.text = detail.rawSkillMarkdown ?? '';
      return;
    }
    if (selectedFile.toUpperCase() == 'SKILL.MD') {
      _editorController.text = detail.rawSkillMarkdown ?? '';
      return;
    }
    _editorController.text = '';
  }

  Future<void> _loadEditorContent(
    SkillPackageDetail detail,
    String relativePath,
  ) async {
    if (relativePath.toUpperCase() == 'SKILL.MD') {
      _editorController.text = detail.rawSkillMarkdown ?? '';
      return;
    }
    final content = await widget.controller.loadFileContent(
      skillId: detail.ref.id,
      relativePath: relativePath,
    );
    if (!mounted || _selectedFilePath != relativePath) {
      return;
    }
    _editorController.text = content ?? '';
  }

  Future<void> _showCreateDialog() async {
    _createController.clear();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Skill Package'),
          content: TextField(
            controller: _createController,
            decoration: const InputDecoration(
              labelText: 'Package name',
              hintText: 'sleep_tracker',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_createController.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    final markdown = [
      '---',
      'name: $trimmed',
      'description: New skill package.',
      'tools_required: []',
      '---',
      '',
      '# ${trimmed.replaceAll('_', ' ')}',
      '',
      'Describe the skill here.',
      '',
    ].join('\n');
    await widget.controller.createPackage(
      id: trimmed,
      markdown: markdown,
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete skill package?'),
          content: const Text(
            'This permanently removes the writable skill folder.',
          ),
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
        );
      },
    );
    return result ?? false;
  }
}

class _MobileHeader extends StatelessWidget {
  const _MobileHeader({
    required this.title,
    required this.onRefresh,
    required this.onCreate,
  });

  final String title;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SkillsListPane extends StatelessWidget {
  const _SkillsListPane({
    required this.packages,
    required this.selectedId,
    required this.onRefresh,
    required this.onCreate,
    required this.onSelect,
  });

  final List<SkillPackageRef> packages;
  final String? selectedId;
  final Future<void> Function() onRefresh;
  final VoidCallback onCreate;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Skills',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh skills',
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: packages.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final package = packages[index];
              return _SkillListTile(
                package: package,
                selected: selectedId == package.id,
                onTap: () => onSelect(package.id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SkillListTile extends StatelessWidget {
  const _SkillListTile({
    required this.package,
    required this.selected,
    required this.onTap,
  });

  final SkillPackageRef package;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validation = package.validationSummary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Badge(label: package.isEnabled ? 'enabled' : 'disabled'),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(label: _sourceLabel(package.sourceType)),
                _Badge(label: package.isWritable ? 'writable' : 'read-only'),
                if (validation.hasIssues)
                  _Badge(
                    label: validation.isValid ? 'warnings' : 'invalid',
                  )
                else
                  _Badge(label: 'valid'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              validation.hasIssues
                  ? validation.issues.first.message
                  : 'Package is valid and ready.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(SkillSourceType type) {
    return switch (type) {
      SkillSourceType.builtin => 'builtin',
      SkillSourceType.user => 'local',
    };
  }
}

class _SkillDetailView extends StatelessWidget {
  const _SkillDetailView({
    required this.package,
    required this.selectedFilePath,
    required this.editorController,
    required this.dirty,
    required this.mobileMode,
    required this.onPickFile,
    required this.onEditorChanged,
    required this.onSave,
    required this.onToggleEnabled,
    required this.onDelete,
  });

  final SkillPackageDetail package;
  final String? selectedFilePath;
  final TextEditingController editorController;
  final bool dirty;
  final bool mobileMode;
  final ValueChanged<String> onPickFile;
  final VoidCallback onEditorChanged;
  final Future<void> Function() onSave;
  final Future<void> Function() onToggleEnabled;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedNode = package.fileTree
        .where((entry) => entry.relativePath == selectedFilePath)
        .cast<SkillFileNode?>()
        .firstWhere((entry) => entry != null, orElse: () => null);
    final editable = selectedNode?.isEditable ?? false;
    final detailBody = mobileMode
        ? _buildMobileBody(context, theme, selectedNode, editable)
        : _buildDesktopBody(context, theme, selectedNode, editable);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: detailBody,
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final badges = <Widget>[
      _Badge(label: package.ref.sourceType.name),
      _Badge(label: package.ref.isEnabled ? 'enabled' : 'disabled'),
      _Badge(label: package.ref.isWritable ? 'writable' : 'read-only'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          package.ref.displayName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: badges),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: package.ref.isWritable ? onSave : null,
              icon: const Icon(Icons.save),
              label: Text(dirty ? 'Save*' : 'Save'),
            ),
            OutlinedButton.icon(
              onPressed: onToggleEnabled,
              icon: const Icon(Icons.toggle_on),
              label: Text(package.ref.isEnabled ? 'Disable' : 'Enable'),
            ),
            OutlinedButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileBody(
    BuildContext context,
    ThemeData theme,
    SkillFileNode? selectedNode,
    bool editable,
  ) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildHeader(context, theme),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Overview',
          child: Text(
            package.permissionsAndToolsSummary,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        _SectionCard(
          title: 'Files',
          child: _FileTreePane(
            nodes: package.fileTree,
            selectedPath: selectedFilePath,
            onPickFile: onPickFile,
          ),
        ),
        _SectionCard(
          title: 'Editor',
          child: SizedBox(
            height: 280,
            child: TextField(
              controller: editorController,
              readOnly: !editable,
              expands: true,
              maxLines: null,
              minLines: null,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: selectedNode == null
                    ? 'Select a file to edit.'
                    : editable
                        ? 'Edit ${selectedNode.relativePath}'
                        : 'This file is read-only.',
              ),
              onChanged: (_) => onEditorChanged(),
            ),
          ),
        ),
        _SectionCard(
          title: 'Validation',
          child: _ValidationContent(package: package),
        ),
        _SectionCard(
          title: 'Status',
          child: Text(
            package.validationSummary.hasIssues
                ? package.validationSummary.issues.first.message
                : 'No issues detected.',
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopBody(
    BuildContext context,
    ThemeData theme,
    SkillFileNode? selectedNode,
    bool editable,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, theme),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: ListView(
                  children: [
                    _SectionCard(
                      title: 'Overview',
                      child: Text(package.permissionsAndToolsSummary),
                    ),
                    _SectionCard(
                      title: 'Files',
                      child: _FileTreePane(
                        nodes: package.fileTree,
                        selectedPath: selectedFilePath,
                        onPickFile: onPickFile,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 5,
                child: ListView(
                  children: [
                    _SectionCard(
                      title: 'Editor',
                      child: SizedBox(
                        height: 360,
                        child: TextField(
                          controller: editorController,
                          readOnly: !editable,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText: selectedNode == null
                                ? 'Select a file to edit.'
                                : editable
                                    ? 'Edit ${selectedNode.relativePath}'
                                    : 'This file is read-only.',
                          ),
                          onChanged: (_) => onEditorChanged(),
                        ),
                      ),
                    ),
                    _SectionCard(
                      title: 'Validation',
                      child: _ValidationContent(package: package),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FileTreePane extends StatelessWidget {
  const _FileTreePane({
    required this.nodes,
    required this.selectedPath,
    required this.onPickFile,
  });

  final List<SkillFileNode> nodes;
  final String? selectedPath;
  final ValueChanged<String> onPickFile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final node in nodes)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: node.relativePath == selectedPath,
            title: Text(
              node.relativePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('${node.kind.name} • ${node.size} bytes'),
            trailing: node.kind == SkillFileKind.text
                ? const Icon(Icons.edit, size: 16)
                : Icon(
                    node.kind == SkillFileKind.directory
                        ? Icons.folder_outlined
                        : Icons.block,
                    size: 16,
                  ),
            onTap: node.kind == SkillFileKind.directory
                ? null
                : () => onPickFile(node.relativePath),
          ),
      ],
    );
  }
}

class _ValidationContent extends StatelessWidget {
  const _ValidationContent({required this.package});

  final SkillPackageDetail package;

  @override
  Widget build(BuildContext context) {
    final issues = package.validationSummary.issues;
    if (issues.isEmpty) {
      return const Text('Package is valid.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final issue in issues)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${issue.isError ? 'Error' : 'Warning'}: ${issue.message}',
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            child,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
