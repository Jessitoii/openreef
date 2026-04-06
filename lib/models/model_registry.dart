import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/models/model_descriptor.dart';

class ModelRegistry {
  const ModelRegistry({this.models = _defaultModels});

  final List<ModelDescriptor> models;

  ModelDescriptor? findById(String id) {
    for (final model in models) {
      if (model.id == id) {
        return model;
      }
    }
    return null;
  }

  static const List<ModelDescriptor> _defaultModels = <ModelDescriptor>[
    ModelDescriptor(
      id: 'gemma-4-e2b-it',
      name: 'Gemma 4 E2B IT',
      downloadUrl:
          'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true',
      modelType: ModelType.gemmaIt,
      fileType: ModelFileType.task,
      storageFileName: 'gemma_4_e2b_it.task',
      expectedFileSizeBytes: 2583 * 1024 * 1024,
      contextWindow: 32000,
      minRamGb: 3,
      bestFor: 'Default assistant with strong speed, coding, and reasoning.',
      hardwareNotes: 'Recommended baseline model for modern Android phones.',
    ),
    ModelDescriptor(
      id: 'function-gemma-270m-it',
      name: 'FunctionGemma 270M IT',
      downloadUrl:
          'https://huggingface.co/JackJ1/functiongemma-270m-it-mobile-actions-litertlm/resolve/main/mobile-actions_q8_ekv1024.litertlm?download=true',
      modelType: ModelType.functionGemma,
      fileType: ModelFileType.task,
      storageFileName: 'function_gemma_270m_it.task',
      expectedFileSizeBytes: 262 * 1024 * 1024,
      contextWindow: 8192,
      minRamGb: 2,
      bestFor: 'Function-calling focused assistant for tool execution.',
      hardwareNotes: 'Lightweight model optimized for structured tool calls.',
    ),
  ];
}
