import 'package:flutter_gemma/flutter_gemma.dart';

abstract class SemanticTextEmbedder {
  Future<List<double>> embedQuery(String text);

  Future<List<double>> embedDocument(String text);

  String get modelId;
}

class OnDeviceSemanticTextEmbedder implements SemanticTextEmbedder {
  OnDeviceSemanticTextEmbedder({EmbeddingModel? model, String? modelId})
    : _model = model,
      _modelId = modelId;

  EmbeddingModel? _model;
  final String? _modelId;

  @override
  String get modelId => _modelId ?? 'flutter_gemma_active_embedder';

  @override
  Future<List<double>> embedDocument(String text) async {
    final model = await _ensureModel();
    return model.generateEmbedding(
      text,
      taskType: TaskType.retrievalDocument,
    );
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    final model = await _ensureModel();
    return model.generateEmbedding(
      text,
      taskType: TaskType.retrievalQuery,
    );
  }

  Future<EmbeddingModel> _ensureModel() async {
    final current = _model;
    if (current != null) {
      return current;
    }
    final model = await FlutterGemma.getActiveEmbedder();
    _model = model;
    return model;
  }
}
