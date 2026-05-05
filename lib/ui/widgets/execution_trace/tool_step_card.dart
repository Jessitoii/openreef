import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/widgets/execution_trace/execution_step_card.dart';

class ToolStepCard extends StatelessWidget {
  const ToolStepCard({
    required this.step,
    required this.expanded,
    required this.onToggleExpanded,
    super.key,
  });

  final ExecutionTraceStep step;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    if (step.details.isEmpty) {
      return ExecutionStepCard(step: step);
    }

    final theme = Theme.of(context);
    return Column(
      key: Key('tool-step-${step.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggleExpanded,
          child: Stack(
            alignment: Alignment.centerRight,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 42),
                child: ExecutionStepCard(step: step),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            key: Key('tool-step-details-${step.id}'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.28,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final detail in step.details)
                  _DetailChip(name: detail.name, value: detail.value),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.name, required this.value});

  final String name;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        '$name: $value',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
