enum ComposerAttachmentType { image, audio, document, voiceMessage }

enum ComposerAttachmentAvailability {
  available,
  unsupportedByModel,
  unsupportedByRuntime,
  unavailable,
}

class ComposerAttachmentDescriptor {
  const ComposerAttachmentDescriptor({
    required this.id,
    required this.type,
    required this.displayName,
    this.sizeBytes,
    this.mimeType,
    this.sourceUri,
  });

  final String id;
  final ComposerAttachmentType type;
  final String displayName;
  final int? sizeBytes;
  final String? mimeType;
  final String? sourceUri;
}

class ComposerSubmission {
  const ComposerSubmission({
    required this.text,
    this.attachments = const <ComposerAttachmentDescriptor>[],
  });

  final String text;
  final List<ComposerAttachmentDescriptor> attachments;

  bool get isTextOnly => attachments.isEmpty;
  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;
}
