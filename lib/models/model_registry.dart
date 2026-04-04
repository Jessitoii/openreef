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
      storageFileName: 'gemma_4_e2b_it.task',
      expectedFileSizeBytes: 2583 * 1024 * 1024,
      contextWindow: 32000,
      minRamGb: 3,
      bestFor: 'Default assistant with strong speed, coding, and reasoning.',
      hardwareNotes: 'Recommended baseline model for modern Android phones.',
    ),
    ModelDescriptor(
      id: 'gemma-3n-e2b-it',
      name: 'Gemma 3n E2B IT',
      downloadUrl:
          'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm?download=true',
      storageFileName: 'gemma_3n_e2b_it.task',
      expectedFileSizeBytes: 1536 * 1024 * 1024,
      contextWindow: 32000,
      minRamGb: 3,
      bestFor: 'Multimodal-friendly option for text, image, and audio tasks.',
      hardwareNotes: 'Good fit when future multimodal features matter.',
    ),
    ModelDescriptor(
      id: 'gemma-3-1b-it',
      name: 'Gemma 3 1B IT',
      downloadUrl:
          'https://huggingface.co/litert-community/Gemma3-1B-IT/resolve/main/Gemma3-1B-IT_q4_ekv1280_generic.litertlm?download=true',
      storageFileName: 'gemma_3_1b_it.task',
      expectedFileSizeBytes: 658 * 1024 * 1024,
      contextWindow: 8000,
      minRamGb: 2,
      bestFor: 'Lower-end devices and fast lightweight on-device chat.',
      hardwareNotes: 'Fallback choice for constrained RAM devices.',
    ),
    ModelDescriptor(
      id: 'phi-4-mini-it',
      name: 'Phi-4 Mini IT',
      downloadUrl:
          'https://huggingface.co/litert-community/Phi-4-mini-instruct-litert-lm/resolve/main/phi-4-mini-instruct.litertlm?download=true',
      storageFileName: 'phi_4_mini_it.task',
      expectedFileSizeBytes: 2147 * 1024 * 1024,
      contextWindow: 16000,
      minRamGb: 4,
      bestFor: 'Reasoning-heavy tasks and longer structured planning.',
      hardwareNotes:
          'Best on devices with comfortable thermal and RAM headroom.',
    ),
  ];
}
