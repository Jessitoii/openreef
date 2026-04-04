import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/mock_chat_session.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.chatSession,
    super.key,
  });

  final MockChatSession chatSession;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _lastMessageCount = 0;

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
        if (messages.length != _lastMessageCount) {
          _lastMessageCount = messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
            }
          });
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChatHeader(status: widget.chatSession.status),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.fiber_manual_record,
                              size: 12,
                              color: widget.chatSession.status ==
                                      ChatSessionStatus.idle
                                  ? ReefPalette.darkSuccess
                                  : ReefPalette.coral,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _statusLabel(widget.chatSession.status),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'session: main',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            return _TranscriptBubble(message: messages[index]);
                          },
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
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
                            'Ask OpenReef to plan, search memory, or configure voice...',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: const Key('chat-send-button'),
                    onPressed: _submitMessage,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 16),
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

  Future<void> _submitMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) {
      return;
    }

    _composerController.clear();
    await widget.chatSession.sendMessage(text);
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.status});

  final ChatSessionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '> OPENREEF_TERMINAL',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Offline-first agent console. UI is live, AgentLoop hookup is mocked, and settings map cleanly to future tools.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _HeaderChip(
                  label: 'model: offline',
                  accent: theme.colorScheme.primary,
                ),
                _HeaderChip(
                  label: 'voice: local',
                  accent: ReefPalette.darkSuccess,
                ),
                _HeaderChip(
                  label: 'status: ${_statusLabel(status).toLowerCase()}',
                  accent: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.label,
    required this.accent,
  });

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

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.message});

  final ChatTranscriptMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.sender == ChatMessageSender.user;
    final isSystem = message.sender == ChatMessageSender.system;
    final alignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: alignment,
                children: [
                  Text(
                    message.text,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTimestamp(message.timestamp),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

String _statusLabel(ChatSessionStatus status) {
  switch (status) {
    case ChatSessionStatus.idle:
      return 'IDLE';
    case ChatSessionStatus.planning:
      return 'PLANNING';
    case ChatSessionStatus.toolRouting:
      return 'TOOL ROUTING';
    case ChatSessionStatus.completed:
      return 'COMPLETE';
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
