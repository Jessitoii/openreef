import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';

class StreamingAssistantBubble extends StatelessWidget {
  const StreamingAssistantBubble({
    required this.text,
    required this.timeLabel,
    required this.isStreaming,
    super.key,
  });

  final String text;
  final String timeLabel;
  final bool isStreaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleText = text.trim().isEmpty && isStreaming ? 'Thinking' : text;

    return Container(
      key: const Key('streaming-assistant-bubble'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isStreaming
              ? ReefPalette.coral.withValues(alpha: 0.26)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(visibleText, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isStreaming) ...[
                SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ReefPalette.coral,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                isStreaming ? 'Streaming' : timeLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
