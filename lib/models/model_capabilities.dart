class ModelInputCapabilities {
  const ModelInputCapabilities({
    this.supportsTextInput = true,
    this.supportsImageInput = false,
    this.supportsAudioInput = false,
    this.supportsDocumentInput = false,
  });

  static const textOnly = ModelInputCapabilities();

  final bool supportsTextInput;
  final bool supportsImageInput;
  final bool supportsAudioInput;
  final bool supportsDocumentInput;
}
