import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';

class ExecutionStepCard extends StatelessWidget {
  const ExecutionStepCard({required this.step, super.key});

  final ExecutionTraceStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForStatus(theme);

    return Container(
      key: Key('execution-step-${step.id}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_iconForStatus(), size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (step.summary.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorForStatus(ThemeData theme) {
    return switch (step.status) {
      ExecutionStepStatus.completed => ReefPalette.success,
      ExecutionStepStatus.failed => theme.colorScheme.error,
      ExecutionStepStatus.approvalRequired => ReefPalette.coral,
      ExecutionStepStatus.running => ReefPalette.coral,
    };
  }

  IconData _iconForStatus() {
    return switch (step.status) {
      ExecutionStepStatus.completed => Icons.check_circle_outline,
      ExecutionStepStatus.failed => Icons.error_outline,
      ExecutionStepStatus.approvalRequired => Icons.verified_user_outlined,
      ExecutionStepStatus.running => Icons.autorenew,
    };
  }
}
