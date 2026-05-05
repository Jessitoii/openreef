class ModelInputCapabilities {
  const ModelInputCapabilities({
    this.supportsTextInput = true,
    this.supportsImageInput = false,
    this.supportsAudioInput = false,
    this.supportsDocumentInput = false,
  });

  static const textOnly = ModelInputCapabilities();
  static const textOnlyFallbackMetadata = ModelCapabilityMetadata(
    input: textOnly,
    supportsFunctionCalling: false,
    contextWindow: 0,
    ramEstimateGb: 0,
  );

  final bool supportsTextInput;
  final bool supportsImageInput;
  final bool supportsAudioInput;
  final bool supportsDocumentInput;

  bool get supportsVision => supportsImageInput;
  bool get supportsAudio => supportsAudioInput;
  bool get supportsDocuments => supportsDocumentInput;
}

class ModelCapabilityMetadata {
  const ModelCapabilityMetadata({
    required this.input,
    required this.supportsFunctionCalling,
    required this.contextWindow,
    required this.ramEstimateGb,
  });

  final ModelInputCapabilities input;
  final bool supportsFunctionCalling;
  final int contextWindow;
  final double ramEstimateGb;

  List<String> get badges {
    return <String>[
      if (input.supportsTextInput) 'Text',
      if (input.supportsImageInput) 'Vision',
      if (input.supportsAudioInput) 'Audio',
      if (input.supportsDocumentInput) 'Document',
      if (supportsFunctionCalling) 'Function calling',
      if (contextWindow > 0) 'Context ${contextWindow ~/ 1000}K',
      'RAM ${ramEstimateGb.toStringAsFixed(1)} GB',
    ];
  }
}
