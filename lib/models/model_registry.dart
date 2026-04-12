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

  List<ModelDescriptor> get generationModels => models
      .where((model) => model.task == ReefModelTask.generation)
      .toList(growable: false);

  List<ModelDescriptor> get embeddingModels => models
      .where((model) => model.task == ReefModelTask.embedding)
      .toList(growable: false);

  ModelDescriptor? get defaultEmbeddingModel {
    final embeddings = embeddingModels;
    for (final model in embeddings) {
      if (model.recommended) {
        return model;
      }
    }
    return embeddings.isEmpty ? null : embeddings.first;
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
      recommended: true,
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
    ModelDescriptor(
      id: 'gecko-256',
      name: 'Gecko 256',
      downloadUrl:
          'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_256_quant.tflite',
      tokenizerUrl:
          'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model',
      iosTokenizerUrl:
          'https://github.com/DenisovAV/flutter_gemma/releases/download/v0.12.5/gecko_tokenizer.json',
      modelType: ModelType.general,
      fileType: ModelFileType.binary,
      storageFileName: 'Gecko_256_quant.tflite',
      expectedFileSizeBytes: 114141184,
      contextWindow: 0,
      minRamGb: 1,
      bestFor:
          'Default semantic retrieval for native tools, MCP tools, and skills.',
      hardwareNotes:
          'Public LiteRT embedding model. No Hugging Face token required.',
      task: ReefModelTask.embedding,
      multilingual: false,
      recommended: true,
    ),
    ModelDescriptor(
      id: 'gecko-512',
      name: 'Gecko 512',
      downloadUrl:
          'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/Gecko_512_quant.tflite',
      tokenizerUrl:
          'https://huggingface.co/litert-community/Gecko-110m-en/resolve/main/sentencepiece.model',
      iosTokenizerUrl:
          'https://github.com/DenisovAV/flutter_gemma/releases/download/v0.12.5/gecko_tokenizer.json',
      modelType: ModelType.general,
      fileType: ModelFileType.binary,
      storageFileName: 'Gecko_512_quant.tflite',
      expectedFileSizeBytes: 120432640,
      contextWindow: 0,
      minRamGb: 1,
      bestFor:
          'Higher-context semantic retrieval with the public Gecko embedder.',
      hardwareNotes:
          'Public LiteRT embedding model. No Hugging Face token required.',
      task: ReefModelTask.embedding,
      multilingual: false,
    ),
    ModelDescriptor(
      id: 'embeddinggemma-300m-256',
      name: 'EmbeddingGemma 300M 256',
      downloadUrl:
          'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/embeddinggemma-300M_seq256_mixed-precision.tflite',
      tokenizerUrl:
          'https://huggingface.co/litert-community/embeddinggemma-300m/resolve/main/sentencepiece.model',
      iosTokenizerUrl:
          'https://github.com/DenisovAV/flutter_gemma/releases/download/v0.12.5/embeddinggemma_tokenizer.json',
      modelType: ModelType.general,
      fileType: ModelFileType.binary,
      storageFileName: 'embeddinggemma-300M_seq256_mixed-precision.tflite',
      expectedFileSizeBytes: 0,
      contextWindow: 0,
      minRamGb: 2,
      bestFor: 'Gated higher-quality semantic retrieval.',
      hardwareNotes:
          'Requires Hugging Face access to litert-community/embeddinggemma-300m.',
      task: ReefModelTask.embedding,
      multilingual: true,
      requiresHfToken: true,
    ),
  ];
}
