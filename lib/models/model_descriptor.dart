import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/models/model_capabilities.dart';

enum ReefModelTask { generation, embedding }

class ModelDescriptor {
  const ModelDescriptor({
    required this.id,
    required this.name,
    required this.downloadUrl,
    required this.modelType,
    required this.fileType,
    required this.storageFileName,
    required this.expectedFileSizeBytes,
    required this.contextWindow,
    required this.minRamGb,
    required this.bestFor,
    this.hardwareNotes,
    this.task = ReefModelTask.generation,
    this.multilingual = false,
    this.requiresHfToken = false,
    this.recommended = false,
    this.defaultEnabled = true,
    this.tokenizerUrl,
    this.iosTokenizerUrl,
    this.inputCapabilities = ModelInputCapabilities.textOnly,
  });

  final String id;
  final String name;
  final String downloadUrl;
  final ModelType modelType;
  final ModelFileType fileType;
  final String storageFileName;
  final int expectedFileSizeBytes;
  final int contextWindow;
  final double minRamGb;
  final String bestFor;
  final String? hardwareNotes;
  final ReefModelTask task;
  final bool multilingual;
  final bool requiresHfToken;
  final bool recommended;
  final bool defaultEnabled;
  final String? tokenizerUrl;
  final String? iosTokenizerUrl;
  final ModelInputCapabilities inputCapabilities;
}

class InstalledModelRecord {
  const InstalledModelRecord({
    required this.descriptor,
    required this.modelId,
    required this.fileSizeBytes,
    required this.installedAt,
    this.path,
  });

  final ModelDescriptor descriptor;
  final String modelId;
  final int fileSizeBytes;
  final DateTime installedAt;
  final String? path;
}
