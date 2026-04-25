import 'package:flutter/material.dart';
import 'package:openreef/models/model_capabilities.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/chat/attachment_runtime_support.dart';
import 'package:openreef/ui/chat/composer_capability_resolver.dart';
import 'package:openreef/ui/chat/composer_models.dart';
import 'package:openreef/ui/chat/composer_submission_validator.dart';
import 'package:openreef/ui/components/app_components.dart';
import 'package:openreef/ui/chat_session_port.dart';
import 'package:openreef/ui/viewmodels/chat_viewmodels.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.chatSession,
    required this.sessionTitle,
    required this.lastModified,
    required this.onSendMessage,
    this.onSendComposerSubmission,
    this.capabilityResolver,
    this.initialComposerAttachments = const <ComposerAttachmentDescriptor>[],
    super.key,
  });

  final ChatSessionPort chatSession;
  final String sessionTitle;
  final DateTime lastModified;
  final Future<void> Function(String message) onSendMessage;
  final Future<void> Function(ComposerSubmission submission)?
  onSendComposerSubmission;
  final ComposerCapabilityResolver? capabilityResolver;
  final List<ComposerAttachmentDescriptor> initialComposerAttachments;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Set<String> _expandedActivityIds = <String>{};
  final ComposerSubmissionValidator _submissionValidator =
      const ComposerSubmissionValidator();
  late List<ComposerAttachmentDescriptor> _composerAttachments;
  int _lastContentFootprint = 0;

  @override
  void initState() {
    super.initState();
    _composerAttachments = List<ComposerAttachmentDescriptor>.from(
      widget.initialComposerAttachments,
    );
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submitMessage() {
    final text = _composerController.text.trim();
    final submission = ComposerSubmission(
      text: text,
      attachments: List<ComposerAttachmentDescriptor>.unmodifiable(
        _composerAttachments,
      ),
    );
    if (submission.isEmpty) return;

    final validation = _submissionValidator.validate(
      submission,
      _capabilityResolver.resolve(),
    );
    if (validation.hasRejectedAttachments) {
      _showUnsupportedAttachmentMessage(validation.rejectedAttachments.first);
      return;
    }

    if (validation.submission.isEmpty) return;

    _composerController.clear();
    setState(() {
      _composerAttachments.clear();
    });

    if (validation.submission.isTextOnly) {
      widget.onSendMessage(validation.submission.text);
    } else {
      final sendSubmission =
          widget.onSendComposerSubmission ??
          widget.chatSession.sendComposerSubmission;
      sendSubmission(validation.submission);
    }
  }

  ComposerCapabilityResolver get _capabilityResolver {
    return widget.capabilityResolver ??
        const ComposerCapabilityResolver(
          modelCapabilityProvider: StaticActiveModelCapabilityProvider(
            ModelInputCapabilities.textOnly,
          ),
          runtimeSupport: DefaultAttachmentRuntimeSupport(),
        );
  }

  void _showUnsupportedAttachmentMessage(RejectedComposerAttachment rejected) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_disabledMessageFor(rejected.attachment.type))),
    );
  }

  Future<void> _openAttachmentSheet() {
    final capabilities = _capabilityResolver.resolve();
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              key: const Key('chat-attachment-sheet'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add attachment',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                _AttachmentActionTile(
                  key: const Key('attachment-row-image'),
                  type: ComposerAttachmentType.image,
                  title: 'Image',
                  subtitle: _subtitleFor(
                    ComposerAttachmentType.image,
                    capabilities.availabilityFor(ComposerAttachmentType.image),
                  ),
                  availability: capabilities.availabilityFor(
                    ComposerAttachmentType.image,
                  ),
                ),
                _AttachmentActionTile(
                  key: const Key('attachment-row-document'),
                  type: ComposerAttachmentType.document,
                  title: 'Document',
                  subtitle: _subtitleFor(
                    ComposerAttachmentType.document,
                    capabilities.availabilityFor(
                      ComposerAttachmentType.document,
                    ),
                  ),
                  availability: capabilities.availabilityFor(
                    ComposerAttachmentType.document,
                  ),
                ),
                _AttachmentActionTile(
                  key: const Key('attachment-row-audio'),
                  type: ComposerAttachmentType.audio,
                  title: 'Voice / Audio',
                  subtitle: _subtitleFor(
                    ComposerAttachmentType.audio,
                    capabilities.availabilityFor(ComposerAttachmentType.audio),
                  ),
                  availability: capabilities.availabilityFor(
                    ComposerAttachmentType.audio,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _subtitleFor(
    ComposerAttachmentType type,
    ComposerAttachmentAvailability availability,
  ) {
    return switch (availability) {
      ComposerAttachmentAvailability.available =>
        'Ready when a picker is wired for this attachment type',
      ComposerAttachmentAvailability.unsupportedByModel => switch (type) {
        ComposerAttachmentType.image =>
          'Switch to a model with image support to attach photos',
        ComposerAttachmentType.audio =>
          'Switch to a model with audio support to attach voice files',
        ComposerAttachmentType.document =>
          'Switch to a model with document support to attach files',
      },
      ComposerAttachmentAvailability.unsupportedByRuntime => switch (type) {
        ComposerAttachmentType.image => 'Image attachments are not wired yet',
        ComposerAttachmentType.audio =>
          'Voice and audio attachments are not wired yet',
        ComposerAttachmentType.document =>
          'Document attachments are not wired yet',
      },
      ComposerAttachmentAvailability.unavailable =>
        'Current model only supports text',
    };
  }

  String _disabledMessageFor(ComposerAttachmentType type) {
    return switch (type) {
      ComposerAttachmentType.image => 'Image attachments are not available yet',
      ComposerAttachmentType.audio =>
        'Voice and audio attachments are not available yet',
      ComposerAttachmentType.document =>
        'Document attachments are not available yet',
    };
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
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
            }
          });
        }

        final combinedCount =
            messages.length +
            activities.length +
            (widget.chatSession.pendingApprovalOrNull != null ? 1 : 0);

        return Column(
          children: [
            AppPageHeader(title: widget.sessionTitle),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
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
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: _ApprovalCard(
                        chatSession: widget.chatSession,
                        approval: ApprovalViewModel.fromDomain(
                          widget.chatSession.pendingApprovalOrNull!,
                        ),
                        expanded: _expandedActivityIds.contains(
                          widget.chatSession.pendingApprovalOrNull!.toolId,
                        ),
                        onToggleExpand: () {
                          setState(() {
                            final id = widget
                                .chatSession
                                .pendingApprovalOrNull!
                                .toolId;
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
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_composerAttachments.isNotEmpty) ...[
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final attachment in _composerAttachments)
                          _AttachmentChip(
                            attachment: attachment,
                            onRemove: () {
                              setState(() {
                                _composerAttachments.removeWhere(
                                  (entry) => entry.id == attachment.id,
                                );
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        key: const Key('chat-attachment-button'),
                        tooltip: 'Add attachment',
                        onPressed: _openAttachmentSheet,
                        icon: const Icon(Icons.attach_file),
                      ),
                      const SizedBox(width: AppSpacing.xs),
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
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(16),
                              ),
                            ),
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
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AttachmentActionTile extends StatelessWidget {
  const _AttachmentActionTile({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.availability,
    super.key,
  });

  final ComposerAttachmentType type;
  final String title;
  final String subtitle;
  final ComposerAttachmentAvailability availability;

  @override
  Widget build(BuildContext context) {
    final enabled = availability == ComposerAttachmentAvailability.available;
    return ListTile(
      enabled: enabled,
      leading: Icon(_iconForType(type)),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: enabled ? () => Navigator.of(context).pop() : null,
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final ComposerAttachmentDescriptor attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final label = attachment.sizeBytes == null
        ? attachment.displayName
        : '${attachment.displayName} (${_formatBytes(attachment.sizeBytes!)})';
    return InputChip(
      key: Key('attachment-chip-${attachment.id}'),
      avatar: Icon(_iconForType(attachment.type), size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
      onDeleted: onRemove,
      deleteIcon: Icon(
        Icons.close,
        key: Key('remove-attachment-${attachment.id}'),
        size: 18,
      ),
    );
  }
}

IconData _iconForType(ComposerAttachmentType type) {
  return switch (type) {
    ComposerAttachmentType.image => Icons.image_outlined,
    ComposerAttachmentType.audio => Icons.mic_none_outlined,
    ComposerAttachmentType.document => Icons.description_outlined,
  };
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
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
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          Flexible(
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(viewModel.text, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    viewModel.timeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Approval required',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      approval.humanSummary,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
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
                children: approval.technicalDetails.entries
                    .map(
                      (e) => Text(
                        '${e.key}: ${e.value}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton.secondary(
                key: const Key('approval-reject-button'),
                onPressed: chatSession.rejectPendingApprovalIfSupported,
                label: 'Reject',
              ),
              const SizedBox(width: AppSpacing.sm),
              AppButton.primary(
                key: const Key('approval-approve-button'),
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
