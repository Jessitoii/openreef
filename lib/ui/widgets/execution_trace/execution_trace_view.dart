import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/widgets/execution_trace/approval_step_card.dart';
import 'package:openreef/ui/widgets/execution_trace/execution_step_card.dart';
import 'package:openreef/ui/widgets/execution_trace/tool_step_card.dart';

class ExecutionTraceView extends StatelessWidget {
  const ExecutionTraceView({
    required this.trace,
    required this.expandedStepIds,
    required this.onToggleStep,
    super.key,
  });

  final ExecutionTrace trace;
  final Set<String> expandedStepIds;
  final ValueChanged<String> onToggleStep;

  @override
  Widget build(BuildContext context) {
    if (trace.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: const Key('execution-trace-block'),
            initiallyExpanded: trace.status == ExecutionTraceStatus.running,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            leading: _TraceStatusIcon(status: trace.status),
            title: Text(
              _titleForStatus(trace.status),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              _subtitleForTrace(trace),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              for (final step in trace.steps) ...[
                _StepView(
                  step: step,
                  expanded: expandedStepIds.contains(step.id),
                  onToggleExpanded: () => onToggleStep(step.id),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepView extends StatelessWidget {
  const _StepView({
    required this.step,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final ExecutionTraceStep step;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    return switch (step.kind) {
      ExecutionStepKind.tool => ToolStepCard(
        step: step,
        expanded: expanded,
        onToggleExpanded: onToggleExpanded,
      ),
      ExecutionStepKind.approval => ApprovalStepCard(
        step: step,
        expanded: expanded,
        onToggleExpanded: onToggleExpanded,
      ),
      ExecutionStepKind.step => ExecutionStepCard(step: step),
    };
  }
}

class _TraceStatusIcon extends StatelessWidget {
  const _TraceStatusIcon({required this.status});

  final ExecutionTraceStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      ExecutionTraceStatus.completed => ReefPalette.success,
      ExecutionTraceStatus.failed => theme.colorScheme.error,
      ExecutionTraceStatus.interrupted => theme.colorScheme.onSurfaceVariant,
      ExecutionTraceStatus.running => ReefPalette.coral,
    };
    final icon = switch (status) {
      ExecutionTraceStatus.completed => Icons.check_circle_outline,
      ExecutionTraceStatus.failed => Icons.error_outline,
      ExecutionTraceStatus.interrupted => Icons.pause_circle_outline,
      ExecutionTraceStatus.running => Icons.bolt_outlined,
    };
    return Icon(icon, color: color);
  }
}

String _titleForStatus(ExecutionTraceStatus status) {
  return switch (status) {
    ExecutionTraceStatus.running => 'Execution trace',
    ExecutionTraceStatus.completed => 'Execution complete',
    ExecutionTraceStatus.failed => 'Execution needs attention',
    ExecutionTraceStatus.interrupted => 'Execution interrupted',
  };
}

String _subtitleForTrace(ExecutionTrace trace) {
  final count = trace.steps.length;
  if (trace.summary != null && trace.summary!.isNotEmpty) {
    return '$count ${count == 1 ? 'step' : 'steps'} - ${trace.summary}';
  }
  return '$count ${count == 1 ? 'step' : 'steps'}';
}
