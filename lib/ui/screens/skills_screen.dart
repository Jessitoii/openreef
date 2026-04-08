import 'package:flutter/material.dart';
import 'package:openreef/skills/skill_registry_controller.dart';
import 'package:openreef/skills/skill_runtime_snapshot.dart';
import 'package:openreef/ui/app_theme.dart';

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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<SkillRuntimeSnapshot>>(
      valueListenable: widget.controller.skills,
      builder: (context, skills, _) {
        final installedCount = skills.where((skill) => skill.installed).length;
        final eligibleCount = skills.where((skill) => skill.runtimeEligible).length;
        final activeCount = skills.where((skill) => skill.activeThisTurn).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SkillsHeader(
              skillCount: installedCount,
              runtimeEligibleCount: eligibleCount,
              activeCount: activeCount,
              onRefresh: widget.controller.reload,
            ),
            const SizedBox(height: 12),
            if (skills.isEmpty)
              _EmptyStateCard(
                onRefresh: widget.controller.reload,
              )
            else
              ...skills.map(
                (skill) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SkillCard(
                    skill: skill,
                    onEnabledChanged: (enabled) =>
                        widget.controller.setSkillEnabled(skill.skill.id, enabled),
                  ),
                ),
              ),
            if (skills.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tip: Add new skills by writing SKILL.md files in Documents/skills.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SkillsHeader extends StatelessWidget {
  const _SkillsHeader({
    required this.skillCount,
    required this.runtimeEligibleCount,
    required this.activeCount,
    required this.onRefresh,
  });

  final int skillCount;
  final int runtimeEligibleCount;
  final int activeCount;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SKILL REGISTRY',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Shows the real runtime skills catalog, including enablement, eligibility, and latest-turn matches from the shared agent wiring.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatChip(
                  label: '$skillCount discovered',
                  accent: ReefPalette.coral,
                ),
                _StatChip(
                  label: '$runtimeEligibleCount runtime-eligible',
                  accent: ReefPalette.darkSuccess,
                ),
                _StatChip(
                  label: '$activeCount active this turn',
                  accent: ReefPalette.darkSuccess,
                ),
                _StatChip(
                  label: 'Documents/skills',
                  accent: theme.colorScheme.onSurfaceVariant,
                ),
                FilledButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reload'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  const _SkillCard({
    required this.skill,
    required this.onEnabledChanged,
  });

  final SkillRuntimeSnapshot skill;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = skill.skill.manifest.description.trim().isEmpty
        ? 'No description provided in frontmatter.'
        : skill.skill.manifest.description.trim();
    final tools = skill.skill.manifest.toolsRequired;
    final triggerPatterns = skill.skill.manifest.triggerPatterns;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    skill.skill.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: skill.enabled,
                  onChanged: onEnabledChanged,
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusChip(
                  label: skill.installed ? 'installed' : 'missing',
                  active: skill.installed,
                ),
                _StatusChip(
                  label: skill.enabled ? 'enabled' : 'disabled',
                  active: skill.enabled,
                ),
                _StatusChip(
                  label: skill.runtimeEligible
                      ? 'runtime-eligible'
                      : 'runtime-blocked',
                  active: skill.runtimeEligible,
                ),
                _StatusChip(
                  label: skill.matchedThisTurn
                      ? 'matched this turn'
                      : 'not matched',
                  active: skill.matchedThisTurn,
                ),
                _StatusChip(
                  label: skill.activeThisTurn
                      ? 'active this turn'
                      : 'inactive this turn',
                  active: skill.activeThisTurn,
                ),
              ],
            ),
            if (!skill.runtimeEligible &&
                skill.missingRequiredTools.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Missing required runtime tools',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: skill.missingRequiredTools
                    .map((tool) => _ToolChip(label: tool))
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'trigger_patterns',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  (triggerPatterns.isEmpty ? const <String>['none'] : triggerPatterns)
                      .map((pattern) => _ToolChip(label: pattern))
                      .toList(),
            ),
            const SizedBox(height: 14),
            Text(
              'tools_required',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (tools.isEmpty ? const <String>['none'] : tools)
                  .map((tool) => _ToolChip(label: tool))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = active
        ? ReefPalette.darkSuccess
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: accent,
        ),
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.accent,
  });

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        color: accent.withValues(alpha: 0.12),
      ),
      child: Text(label),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No skills loaded yet.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Drop SKILL.md files in Documents/skills and reload.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Skills'),
            ),
          ],
        ),
      ),
    );
  }
}
