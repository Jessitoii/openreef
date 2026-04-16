import 'package:openreef/ui/chat_session_port.dart';

class MessageViewModel {
  const MessageViewModel({
    required this.id,
    required this.text,
    required this.timeLabel,
    required this.isUser,
    required this.isSystem,
    required this.isStreaming,
  });

  final String id;
  final String text;
  final String timeLabel;
  final bool isUser;
  final bool isSystem;
  final bool isStreaming;

  factory MessageViewModel.fromDomain(ChatTranscriptMessage message) {
    return MessageViewModel(
      id: message.id,
      text: message.text,
      timeLabel:
          '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
      isUser: message.sender == ChatMessageSender.user,
      isSystem: message.sender == ChatMessageSender.system,
      isStreaming: message.isStreaming,
    );
  }
}

class ApprovalViewModel {
  const ApprovalViewModel({
    required this.toolId,
    required this.humanSummary,
    required this.technicalDetails,
  });

  final String toolId;
  final String humanSummary;
  final Map<String, dynamic> technicalDetails;

  factory ApprovalViewModel.fromDomain(PendingToolApproval approval) {
    String summary = 'Action requires your approval: ${approval.toolId}';
    final Map<String, dynamic> args = {};
    for (final entry in approval.arguments.entries) {
      args[entry.key] = entry.value;
    }

    if (approval.toolId.contains('call_number')) {
      final number = args['number'] ?? 'unknown number';
      summary = 'Make a call to $number';
    } else if (approval.toolId.contains('email')) {
      final to = args['to'] ?? 'someone';
      summary = 'Send an email to $to';
    } else if (approval.toolId.contains('file')) {
      summary = 'Access file system';
    }

    return ApprovalViewModel(
      toolId: approval.toolId,
      humanSummary: summary,
      technicalDetails: args,
    );
  }
}

class ActivityViewModel {
  const ActivityViewModel({
    required this.id,
    required this.statusLabel,
    required this.isError,
    required this.isComplete,
  });

  final String id;
  final String statusLabel;
  final bool isError;
  final bool isComplete;

  factory ActivityViewModel.fromDomain(SubAgentActivity activity) {
    String label = activity.label.isNotEmpty ? activity.label : 'Processing...';

    if (activity.status == SubAgentActivityStatus.completed) {
      label = 'Success';
    } else if (activity.status == SubAgentActivityStatus.failed) {
      label = 'Failed to execute tool';
    }

    return ActivityViewModel(
      id: activity.id,
      statusLabel: label,
      isError: activity.status == SubAgentActivityStatus.failed,
      isComplete: activity.status == SubAgentActivityStatus.completed,
    );
  }
}
