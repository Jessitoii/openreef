abstract class AttachmentRuntimeSupport {
  bool get imagePreprocessingAvailable;
  bool get audioPreprocessingAvailable;
  bool get documentPreprocessingAvailable;
}

class DefaultAttachmentRuntimeSupport implements AttachmentRuntimeSupport {
  const DefaultAttachmentRuntimeSupport();

  @override
  bool get imagePreprocessingAvailable => false;

  @override
  bool get audioPreprocessingAvailable => false;

  @override
  bool get documentPreprocessingAvailable => false;
}
