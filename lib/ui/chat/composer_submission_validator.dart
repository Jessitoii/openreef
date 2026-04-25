import 'package:openreef/ui/chat/composer_capability_resolver.dart';
import 'package:openreef/ui/chat/composer_models.dart';

class RejectedComposerAttachment {
  const RejectedComposerAttachment({
    required this.attachment,
    required this.availability,
  });

  final ComposerAttachmentDescriptor attachment;
  final ComposerAttachmentAvailability availability;
}

class ComposerSubmissionValidationResult {
  const ComposerSubmissionValidationResult({
    required this.submission,
    required this.rejectedAttachments,
  });

  final ComposerSubmission submission;
  final List<RejectedComposerAttachment> rejectedAttachments;

  bool get hasRejectedAttachments => rejectedAttachments.isNotEmpty;
}

class ComposerSubmissionValidator {
  const ComposerSubmissionValidator();

  ComposerSubmissionValidationResult validate(
    ComposerSubmission submission,
    ComposerCapabilitySnapshot capabilities,
  ) {
    final accepted = <ComposerAttachmentDescriptor>[];
    final rejected = <RejectedComposerAttachment>[];

    for (final attachment in submission.attachments) {
      final availability = capabilities.availabilityFor(attachment.type);
      if (availability == ComposerAttachmentAvailability.available) {
        accepted.add(attachment);
      } else {
        rejected.add(
          RejectedComposerAttachment(
            attachment: attachment,
            availability: availability,
          ),
        );
      }
    }

    return ComposerSubmissionValidationResult(
      submission: ComposerSubmission(
        text: submission.text,
        attachments: List<ComposerAttachmentDescriptor>.unmodifiable(accepted),
      ),
      rejectedAttachments: List<RejectedComposerAttachment>.unmodifiable(
        rejected,
      ),
    );
  }
}
