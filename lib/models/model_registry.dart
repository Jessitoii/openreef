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
          'https://huggingface.co/litert-community/gemma-3-270m-it/resolve/main/gemma3-270m-it-q8.mediatek.mt6991.litertlm?download=true',
      storageFileName: 'gemma_3n_e2b_it.task',
      expectedFileSizeBytes: 1536 * 1024 * 1024,
      contextWindow: 32000,
      minRamGb: 3,
      bestFor: 'Multimodal-friendly option for text, image, and audio tasks.',
      hardwareNotes: 'Good fit when future multimodal features matter.',
    ),
    ModelDescriptor(
      id: 'gemma-1b-it',
      name: 'Gemma 1B IT (Test)',
      downloadUrl:
          'https://huggingface.co/kikytus/gemma-2b-it-litert-lm/resolve/main/gemma-2b-it-cpu-int4.bin?download=true',
      storageFileName: 'gemma_1b_test.task',
      expectedFileSizeBytes:
          1400 * 1024 * 1024, // Boyut fark etmez, indirene kadar bekleyin
      contextWindow: 4000,
      minRamGb: 2,
      bestFor: 'Test for Memory Limits.',
      hardwareNotes: '-',
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
