abstract class AttachmentRuntimeSupport {
  bool get textRuntimeAvailable;
  bool get imagePreprocessingAvailable;
  bool get audioPreprocessingAvailable;
  bool get documentPreprocessingAvailable;
  bool get speechToTextAvailable;
}

class DefaultAttachmentRuntimeSupport implements AttachmentRuntimeSupport {
  const DefaultAttachmentRuntimeSupport();

  @override
  bool get textRuntimeAvailable => true;

  @override
  bool get imagePreprocessingAvailable => false;

  @override
  bool get audioPreprocessingAvailable => false;

  @override
  bool get documentPreprocessingAvailable => false;

  @override
  bool get speechToTextAvailable => false;
}
