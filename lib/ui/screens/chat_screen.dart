import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.chatSession,
    required this.sessionTitle,
    required this.lastModified,
    required this.onSendMessage,
    super.key,
  });

  final ChatSessionPort chatSession;
  final String sessionTitle;
  final DateTime lastModified;
  final Future<void> Function(String message) onSendMessage;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _expandedActivityIds = <String>{};
  int _lastContentFootprint = 0;

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: widget.chatSession,
      builder: (context, child) {
        final messages = widget.chatSession.messages;
        final activities = widget.chatSession.activities;
        final footprint = messages.length + activities.length;
        if (footprint != _lastContentFootprint) {
          _lastContentFootprint = footprint;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
            }
          });
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SessionHeader(
                status: widget.chatSession.status,
                sessionTitle: widget.sessionTitle,
                lastModified: widget.lastModified,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.colorScheme.surface,
                          theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: Row(
                            children: [
                              _SignalOrb(status: widget.chatSession.status),
                              const SizedBox(width: 10),
                              Text(
                                _statusLabel(widget.chatSession.status),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'session: ${widget.sessionTitle}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (activities.isNotEmpty) ...[
                                Text(
                                  'sub-agents',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                ...activities.map(_buildActivityBlock),
                                const SizedBox(height: 18),
                              ],
                              Text(
                                'transcript',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ..._buildTranscript(messages),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.chatSession.pendingApprovalOrNull != null) ...[
                _PendingApprovalCard(
                  approval: widget.chatSession.pendingApprovalOrNull!,
                  onApprove:
                      widget.chatSession.approvePendingApprovalIfSupported,
                  onReject: widget.chatSession.rejectPendingApprovalIfSupported,
                ),
                const SizedBox(height: 12),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('chat-composer'),
                      controller: _composerController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitMessage(),
                      decoration: const InputDecoration(
                        labelText: 'Prompt',
                        hintText:
                            'Ask OpenReef to plan or search memory. Voice automation is experimental.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const Key('chat-send-button'),
                    onPressed: _submitMessage,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 16,
                      ),
                      child: Text('SEND'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildTranscript(List<ChatTranscriptMessage> messages) {
    return <Widget>[
      for (var index = 0; index < messages.length; index++) ...[
        _TranscriptBubble(message: messages[index]),
        if (index != messages.length - 1) const SizedBox(height: 12),
      ],
    ];
  }

  Widget _buildActivityBlock(SubAgentActivity activity) {
    final theme = Theme.of(context);
    final isExpanded = _expandedActivityIds.contains(activity.id);
    final statusColor = switch (activity.status) {
      SubAgentActivityStatus.running => ReefPalette.coral,
      SubAgentActivityStatus.completed => ReefPalette.darkSuccess,
      SubAgentActivityStatus.failed => theme.colorScheme.error,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: statusColor.withValues(alpha: 0.08),
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              blurRadius: 18,
              offset: const Offset(0, 8),
              color: statusColor.withValues(alpha: 0.06),
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              key: Key('activity-${activity.id}'),
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedActivityIds.remove(activity.id);
                  } else {
                    _expandedActivityIds.add(activity.id);
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      color: statusColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activity.label,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            activity.summary,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ActivityStatusBadge(status: activity.status),
                  ],
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: isExpanded
                  ? Padding(
                      key: ValueKey<String>('${activity.id}-expanded'),
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: activity.details
                            .map(
                              (detail) => Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '> $detail',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) {
      return;
    }

    _composerController.clear();
    await widget.onSendMessage(text);
  }
}

class _PendingApprovalCard extends StatelessWidget {
  const _PendingApprovalCard({
    required this.approval,
    required this.onApprove,
    required this.onReject,
  });

  final PendingToolApproval approval;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final argumentPreview = approval.arguments.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Approval required',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'The agent wants to run `${approval.toolId}`.',
              style: theme.textTheme.bodyMedium,
            ),
            if (argumentPreview.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                argumentPreview,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  key: const Key('approval-reject-button'),
                  onPressed: onReject,
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('approval-approve-button'),
                  onPressed: onApprove,
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.status,
    required this.sessionTitle,
    required this.lastModified,
  });

  final ChatSessionStatus status;
  final String sessionTitle;
  final DateTime lastModified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    ReefPalette.coral.withValues(alpha: 0.10),
                    Colors.transparent,
                    ReefPalette.darkSuccess.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ScanlinePainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '> $sessionTitle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: ReefPalette.darkSuccess.withValues(alpha: 0.6),
                        ),
                        color: ReefPalette.darkSuccess.withValues(alpha: 0.10),
                      ),
                      child: Text(
                        _statusLabel(status).toLowerCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ReefPalette.darkSuccess,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeaderChip(
                      label: 'boot: online',
                      accent: theme.colorScheme.primary,
                    ),
                    _HeaderChip(
                      label: 'voice: experimental',
                      accent: ReefPalette.darkSuccess,
                    ),
                    _HeaderChip(
                      label: 'updated: ${_formatStamp(lastModified)}',
                      accent: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalOrb extends StatelessWidget {
  const _SignalOrb({required this.status});

  final ChatSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final active = switch (status) {
      ChatSessionStatus.idle => ReefPalette.darkSuccess,
      ChatSessionStatus.completed => ReefPalette.darkSuccess,
      ChatSessionStatus.failed => Theme.of(context).colorScheme.error,
      ChatSessionStatus.frozen ||
      ChatSessionStatus.cancelled ||
      ChatSessionStatus.persistenceFailed => Theme.of(
        context,
      ).colorScheme.error,
      ChatSessionStatus.suspended => ReefPalette.coral,
      ChatSessionStatus.planning ||
      ChatSessionStatus.toolRouting ||
      ChatSessionStatus.streaming => ReefPalette.coral,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active,
        boxShadow: [
          BoxShadow(blurRadius: 14, color: active.withValues(alpha: 0.55)),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        color: accent.withValues(alpha: 0.08),
      ),
      child: Text(label),
    );
  }
}

class _ActivityStatusBadge extends StatelessWidget {
  const _ActivityStatusBadge({required this.status});

  final SubAgentActivityStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      SubAgentActivityStatus.running => ('running', ReefPalette.coral),
      SubAgentActivityStatus.completed => ('done', ReefPalette.darkSuccess),
      SubAgentActivityStatus.failed => ('failed', theme.colorScheme.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.14),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.message});

  final ChatTranscriptMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.sender == ChatMessageSender.user;
    final isSystem = message.sender == ChatMessageSender.system;
    final alignment = isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final bubbleColor = isUser
        ? theme.colorScheme.primary.withValues(alpha: 0.14)
        : isSystem
        ? theme.colorScheme.secondaryContainer
        : theme.cardTheme.color ?? theme.colorScheme.surface;

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          _senderLabel(message.sender),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outline),
              boxShadow: [
                if (message.isStreaming)
                  BoxShadow(
                    blurRadius: 16,
                    color: ReefPalette.coral.withValues(alpha: 0.08),
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: alignment,
                children: [
                  _StreamingText(message: message),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (message.isStreaming) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 14,
                          color: ReefPalette.coral,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StreamingText extends StatelessWidget {
  const _StreamingText({required this.message});

  final ChatTranscriptMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Text(
        message.text,
        key: ValueKey<String>('${message.id}:${message.text.length}'),
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    const gap = 8.0;
    for (var y = 0.0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String _statusLabel(ChatSessionStatus status) {
  switch (status) {
    case ChatSessionStatus.idle:
      return 'IDLE';
    case ChatSessionStatus.planning:
      return 'PLANNING';
    case ChatSessionStatus.toolRouting:
      return 'TOOL ROUTING';
    case ChatSessionStatus.streaming:
      return 'STREAMING';
    case ChatSessionStatus.completed:
      return 'COMPLETE';
    case ChatSessionStatus.failed:
      return 'FAILED';
    case ChatSessionStatus.frozen:
      return 'FROZEN';
    case ChatSessionStatus.cancelled:
      return 'CANCELLED';
    case ChatSessionStatus.suspended:
      return 'SUSPENDED';
    case ChatSessionStatus.persistenceFailed:
      return 'PERSISTENCE FAILED';
  }
}

String _senderLabel(ChatMessageSender sender) {
  switch (sender) {
    case ChatMessageSender.user:
      return 'user';
    case ChatMessageSender.assistant:
      return 'assistant';
    case ChatMessageSender.system:
      return 'system';
  }
}

String _formatTimestamp(DateTime timestamp) {
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatStamp(DateTime timestamp) {
  final month = timestamp.month.toString().padLeft(2, '0');
  final day = timestamp.day.toString().padLeft(2, '0');
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');
  return '$month/$day $hour:$minute';
}
