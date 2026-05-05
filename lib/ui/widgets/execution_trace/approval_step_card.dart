import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/widgets/execution_trace/tool_step_card.dart';

class ApprovalStepCard extends StatelessWidget {
  const ApprovalStepCard({
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
    final approvalStep = step.copyWith(
      title: 'Approval required: ${step.title}',
      summary: step.summary,
    );

    return Container(
      key: Key('approval-step-${step.id}'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: ReefPalette.coral.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ToolStepCard(
        step: approvalStep,
        expanded: expanded,
        onToggleExpanded: onToggleExpanded,
      ),
    );
  }
}
