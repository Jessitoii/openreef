import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/models/embedding_model_manager.dart';

abstract class SemanticTextEmbedder {
  Future<List<double>> embedQuery(String text);

  Future<List<double>> embedDocument(String text);

  String get modelId;
}

class OnDeviceSemanticTextEmbedder implements SemanticTextEmbedder {
  OnDeviceSemanticTextEmbedder({EmbeddingModel? model, String? modelId})
    : _model = model,
      _modelId = modelId;

  factory OnDeviceSemanticTextEmbedder.verifiedDefault({
    EmbeddingModel? model,
  }) {
    return OnDeviceSemanticTextEmbedder(
      model: model,
      modelId: defaultCapabilityEmbeddingModelId,
    );
  }

  @Deprecated(
    'Use verifiedDefault(); E5 has no verified FlutterGemma artifact.',
  )
  factory OnDeviceSemanticTextEmbedder.e5Small({EmbeddingModel? model}) {
    return OnDeviceSemanticTextEmbedder.verifiedDefault(model: model);
  }

  static const String defaultCapabilityEmbeddingModelId = 'gecko-256';

  EmbeddingModel? _model;
  final String? _modelId;

  @override
  String get modelId => _modelId ?? 'flutter_gemma_active_embedder';

  @override
  Future<List<double>> embedDocument(String text) async {
    final model = await _ensureModel();
    return model.generateEmbedding(text, taskType: TaskType.retrievalDocument);
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    final model = await _ensureModel();
    return model.generateEmbedding(text, taskType: TaskType.retrievalQuery);
  }

  Future<EmbeddingModel> _ensureModel() async {
    final current = _model;
    if (current != null) {
      return current;
    }
    try {
      if (!FlutterGemma.hasActiveEmbedder()) {
        throw StateError(
          'No active embedding model set. Install/activate $modelId with FlutterGemma.installEmbedder() before agent turns.',
        );
      }
      final model = await FlutterGemma.getActiveEmbedder();
      _model = model;
      return model;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        SemanticEmbeddingUnavailableException(
          modelId,
          'Capability semantic embedding model is unavailable: $error',
        ),
        stackTrace,
      );
    }
  }
}

class ManagedSemanticTextEmbedder implements SemanticTextEmbedder {
  ManagedSemanticTextEmbedder(this._manager);

  final EmbeddingModelManager _manager;

  @override
  String get modelId => _manager.selectedModelId;

  @override
  Future<List<double>> embedDocument(String text) async {
    final embedder = await _manager.requireReadyEmbedder();
    return embedder.embedDocument(text);
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    final embedder = await _manager.requireReadyEmbedder();
    return embedder.embedQuery(text);
  }
}

class SemanticEmbeddingUnavailableException implements Exception {
  const SemanticEmbeddingUnavailableException(this.modelId, this.message);

  final String modelId;
  final String message;

  @override
  String toString() {
    return 'SemanticEmbeddingUnavailableException(modelId=$modelId, message=$message)';
  }
}
