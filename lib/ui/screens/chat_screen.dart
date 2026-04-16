import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/components/app_components.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/viewmodels/chat_viewmodels.dart';

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

  void _submitMessage() {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    _composerController.clear();
    widget.onSendMessage(text);
  }

  @override
  Widget build(BuildContext context) {
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
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }

        final combinedCount = messages.length + activities.length + (widget.chatSession.pendingApprovalOrNull != null ? 1 : 0);

        return Column(
          children: [
            AppPageHeader(title: widget.sessionTitle),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                itemCount: combinedCount,
                itemBuilder: (context, index) {
                  if (index < activities.length) {
                    final activity = activities[index];
                    return _ActivityBubble(
                      viewModel: ActivityViewModel.fromDomain(activity),
                    );
                  }
                  final messageIndex = index - activities.length;
                  if (messageIndex < messages.length) {
                    final message = messages[messageIndex];
                    return _MessageBubble(
                      viewModel: MessageViewModel.fromDomain(message),
                    );
                  }
                  
                  if (widget.chatSession.pendingApprovalOrNull != null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      child: _ApprovalCard(
                        chatSession: widget.chatSession,
                        approval: ApprovalViewModel.fromDomain(widget.chatSession.pendingApprovalOrNull!),
                        expanded: _expandedActivityIds.contains(widget.chatSession.pendingApprovalOrNull!.toolId),
                        onToggleExpand: () {
                          setState(() {
                            final id = widget.chatSession.pendingApprovalOrNull!.toolId;
                            if (_expandedActivityIds.contains(id)) {
                              _expandedActivityIds.remove(id);
                            } else {
                              _expandedActivityIds.add(id);
                            }
                          });
                        },
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
              child: Row(
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
                        hintText: 'Message OpenReef...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppButton.primary(
                    onPressed: _submitMessage,
                    icon: Icons.send,
                    label: 'Send',
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ActivityBubble extends StatelessWidget {
  const _ActivityBubble({required this.viewModel});
  final ActivityViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.isComplete) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: AppBadge(
          label: viewModel.statusLabel,
          isError: viewModel.isError,
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.viewModel});
  final MessageViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = viewModel.isUser;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    viewModel.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    viewModel.timeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.chatSession,
    required this.approval,
    required this.expanded,
    required this.onToggleExpand,
  });

  final ChatSessionPort chatSession;
  final ApprovalViewModel approval;
  final bool expanded;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: ReefPalette.coral),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  approval.humanSummary,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                onPressed: onToggleExpand,
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: approval.technicalDetails.entries.map((e) => Text(
                  '${e.key}: ${e.value}',
                  style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'JetBrainsMono'),
                )).toList(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton.secondary(
                onPressed: chatSession.rejectPendingApprovalIfSupported,
                label: 'Reject',
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton.primary(
                onPressed: chatSession.approvePendingApprovalIfSupported,
                label: 'Approve',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
