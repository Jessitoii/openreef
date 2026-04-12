import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/memory/semantic_text_embedder.dart';
import 'package:openreef/models/hugging_face_token_store.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/settings/settings_controller.dart';

enum EmbeddingModelReadinessStatus {
  notConfigured,
  downloadable,
  requiresAuth,
  downloading,
  installed,
  activating,
  ready,
  failed,
}

class EmbeddingModelReadiness {
  const EmbeddingModelReadiness({
    required this.status,
    this.model,
    this.message,
    this.debugMessage,
    this.hasToken = false,
    this.progress = 0,
  });

  final EmbeddingModelReadinessStatus status;
  final ModelDescriptor? model;
  final String? message;
  final String? debugMessage;
  final bool hasToken;
  final double progress;

  bool get isReady => status == EmbeddingModelReadinessStatus.ready;

  bool get requiresUserAction =>
      status == EmbeddingModelReadinessStatus.notConfigured ||
      status == EmbeddingModelReadinessStatus.downloadable ||
      status == EmbeddingModelReadinessStatus.requiresAuth ||
      status == EmbeddingModelReadinessStatus.failed;
}

class EmbeddingModelNotReadyException implements Exception {
  const EmbeddingModelNotReadyException(this.readiness);

  final EmbeddingModelReadiness readiness;

  String get modelId => readiness.model?.id ?? 'none';

  String get userMessage {
    return readiness.message ??
        switch (readiness.status) {
          EmbeddingModelReadinessStatus.notConfigured =>
            'Choose a semantic retrieval embedding model in Settings.',
          EmbeddingModelReadinessStatus.requiresAuth =>
            'This semantic retrieval model requires a Hugging Face token.',
          EmbeddingModelReadinessStatus.downloadable ||
          EmbeddingModelReadinessStatus.installed =>
            'Install or activate the semantic retrieval embedding model in Settings.',
          EmbeddingModelReadinessStatus.downloading =>
            'The semantic retrieval embedding model is still downloading.',
          EmbeddingModelReadinessStatus.activating =>
            'The semantic retrieval embedding model is still activating.',
          EmbeddingModelReadinessStatus.failed =>
            'The semantic retrieval embedding model is not ready.',
          EmbeddingModelReadinessStatus.ready =>
            'The semantic retrieval embedding model is ready.',
        };
  }

  @override
  String toString() {
    return 'EmbeddingModelNotReadyException(modelId=$modelId, status=${readiness.status.name}, message=$userMessage)';
  }
}

abstract class EmbeddingModelRuntime {
  bool hasActiveEmbedder();

  String? activeEmbedderId();

  Future<EmbeddingModel> getActiveEmbedder();

  Future<bool> isInstalled(ModelDescriptor descriptor);

  Future<void> install({
    required ModelDescriptor descriptor,
    required String? hfToken,
    required void Function(double progress) onProgress,
  });
}

class FlutterGemmaEmbeddingModelRuntime implements EmbeddingModelRuntime {
  const FlutterGemmaEmbeddingModelRuntime();

  @override
  Future<EmbeddingModel> getActiveEmbedder() {
    return FlutterGemma.getActiveEmbedder();
  }

  @override
  bool hasActiveEmbedder() => FlutterGemma.hasActiveEmbedder();

  @override
  String? activeEmbedderId() {
    return FlutterGemmaPlugin.instance.modelManager.activeEmbeddingModel?.name;
  }

  @override
  Future<void> install({
    required ModelDescriptor descriptor,
    required String? hfToken,
    required void Function(double progress) onProgress,
  }) async {
    final tokenizerUrl = descriptor.tokenizerUrl;
    if (tokenizerUrl == null || tokenizerUrl.isEmpty) {
      throw StateError('Embedding model ${descriptor.id} has no tokenizerUrl.');
    }
    final builder = FlutterGemma.installEmbedder()
        .modelFromNetwork(
          descriptor.downloadUrl,
          token: descriptor.requiresHfToken ? hfToken : null,
        )
        .tokenizerFromNetwork(
          tokenizerUrl,
          token: descriptor.requiresHfToken ? hfToken : null,
          iosPath: descriptor.iosTokenizerUrl,
          iosToken: descriptor.requiresHfToken ? hfToken : null,
        )
        .withModelProgress((progress) {
          onProgress((progress.clamp(0, 100) / 100) * 0.9);
        })
        .withTokenizerProgress((progress) {
          onProgress(0.9 + ((progress.clamp(0, 100) / 100) * 0.1));
        });
    await builder.install();
  }

  @override
  Future<bool> isInstalled(ModelDescriptor descriptor) async {
    final tokenizerUrl = descriptor.tokenizerUrl;
    if (tokenizerUrl == null || tokenizerUrl.isEmpty) {
      return false;
    }
    final spec = EmbeddingModelSpec.fromLegacyUrl(
      name: _modelName(descriptor),
      modelUrl: descriptor.downloadUrl,
      tokenizerUrl: tokenizerUrl,
    );
    return FlutterGemmaPlugin.instance.modelManager.isModelInstalled(spec);
  }

  static String _modelName(ModelDescriptor descriptor) {
    return descriptor.storageFileName.contains('.')
        ? descriptor.storageFileName.substring(
            0,
            descriptor.storageFileName.lastIndexOf('.'),
          )
        : descriptor.storageFileName;
  }
}

abstract class EmbeddingModelReadinessProvider {
  Future<EmbeddingModelReadiness> checkReadiness();
}

class EmbeddingModelManager extends ChangeNotifier
    implements EmbeddingModelReadinessProvider {
  EmbeddingModelManager({
    required ModelRegistry registry,
    required SettingsController settingsController,
    required HuggingFaceTokenStore tokenStore,
    EmbeddingModelRuntime runtime = const FlutterGemmaEmbeddingModelRuntime(),
    VoidCallback? onModelChanged,
  }) : _registry = registry,
       _settingsController = settingsController,
       _tokenStore = tokenStore,
       _runtime = runtime,
       _onModelChanged = onModelChanged;

  final ModelRegistry _registry;
  final SettingsController _settingsController;
  final HuggingFaceTokenStore _tokenStore;
  final EmbeddingModelRuntime _runtime;
  final VoidCallback? _onModelChanged;

  EmbeddingModelReadiness _readiness = const EmbeddingModelReadiness(
    status: EmbeddingModelReadinessStatus.notConfigured,
  );
  SemanticTextEmbedder? _embedder;

  List<ModelDescriptor> get models => _registry.embeddingModels;

  EmbeddingModelReadiness get readiness => _readiness;

  ModelDescriptor? get selectedModel {
    final selectedId = _settingsController.settings.semanticEmbeddingModelId;
    if (selectedId != null) {
      return _registry.findById(selectedId);
    }
    return _registry.defaultEmbeddingModel;
  }

  String get selectedModelId => selectedModel?.id ?? 'none';

  Future<void> initialize() async {
    final selected = _settingsController.settings.semanticEmbeddingModelId;
    final defaultModel = _registry.defaultEmbeddingModel;
    if (selected == null && defaultModel != null) {
      _settingsController.updateSemanticEmbeddingModelId(defaultModel.id);
    }
    await refreshReadiness();
  }

  Future<void> selectModel(String modelId) async {
    if (_settingsController.settings.semanticEmbeddingModelId == modelId) {
      return;
    }
    _settingsController.updateSemanticEmbeddingModelId(modelId);
    _embedder = null;
    _onModelChanged?.call();
    await refreshReadiness();
  }

  Future<void> saveHfToken(String modelId, String token) async {
    await _tokenStore.writeTokenForModel(modelId, token);
    await refreshReadiness();
  }

  Future<void> clearHfToken(String modelId) async {
    await _tokenStore.deleteTokenForModel(modelId);
    await refreshReadiness();
  }

  @override
  Future<EmbeddingModelReadiness> checkReadiness() async {
    return refreshReadiness(notify: false);
  }

  Future<EmbeddingModelReadiness> refreshReadiness({bool notify = true}) async {
    final model = selectedModel;
    if (model == null) {
      return _setReadiness(
        const EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.notConfigured,
          message: 'Choose a semantic retrieval embedding model in Settings.',
        ),
        notify: notify,
      );
    }
    final hasToken =
        !model.requiresHfToken || await _tokenStore.hasTokenForModel(model.id);
    if (model.requiresHfToken && !hasToken) {
      return _setReadiness(
        EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.requiresAuth,
          model: model,
          message:
              '${model.name} requires a Hugging Face token before download.',
          hasToken: false,
        ),
        notify: notify,
      );
    }
    try {
      if (_runtime.hasActiveEmbedder() &&
          _runtime.activeEmbedderId() == _activationId(model)) {
        return _setReadiness(
          EmbeddingModelReadiness(
            status: EmbeddingModelReadinessStatus.ready,
            model: model,
            message: '${model.name} is ready for semantic retrieval.',
            hasToken: hasToken,
          ),
          notify: notify,
        );
      }
      final installed = await _runtime.isInstalled(model);
      return _setReadiness(
        EmbeddingModelReadiness(
          status: installed
              ? EmbeddingModelReadinessStatus.installed
              : EmbeddingModelReadinessStatus.downloadable,
          model: model,
          message: installed
              ? 'Activate ${model.name} for semantic retrieval.'
              : 'Install ${model.name} for semantic retrieval.',
          hasToken: hasToken,
        ),
        notify: notify,
      );
    } catch (error) {
      return _setReadiness(
        EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.failed,
          model: model,
          message: 'Semantic retrieval model readiness check failed.',
          debugMessage: error.toString(),
          hasToken: hasToken,
        ),
        notify: notify,
      );
    }
  }

  Future<void> installSelectedModel() async {
    final model = selectedModel;
    if (model == null) {
      throw const EmbeddingModelNotReadyException(
        EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.notConfigured,
          message: 'Choose a semantic retrieval embedding model in Settings.',
        ),
      );
    }
    final hfToken = model.requiresHfToken
        ? await _tokenStore.readTokenForModel(model.id)
        : null;
    if (model.requiresHfToken && (hfToken == null || hfToken.trim().isEmpty)) {
      final readiness = EmbeddingModelReadiness(
        status: EmbeddingModelReadinessStatus.requiresAuth,
        model: model,
        message: '${model.name} requires a Hugging Face token before download.',
      );
      _setReadiness(readiness);
      throw EmbeddingModelNotReadyException(readiness);
    }
    _setReadiness(
      EmbeddingModelReadiness(
        status: EmbeddingModelReadinessStatus.downloading,
        model: model,
        message: 'Downloading ${model.name}.',
      ),
    );
    try {
      await _runtime.install(
        descriptor: model,
        hfToken: hfToken,
        onProgress: (progress) {
          _setReadiness(
            EmbeddingModelReadiness(
              status: EmbeddingModelReadinessStatus.downloading,
              model: model,
              message: 'Downloading ${model.name}.',
              progress: progress.clamp(0, 1),
              hasToken: hfToken != null,
            ),
          );
        },
      );
      _embedder = null;
      _onModelChanged?.call();
      await refreshReadiness();
    } catch (error) {
      _setReadiness(
        EmbeddingModelReadiness(
          status: EmbeddingModelReadinessStatus.failed,
          model: model,
          message: 'Semantic retrieval model install failed.',
          debugMessage: error.toString(),
          hasToken: hfToken != null,
        ),
      );
      rethrow;
    }
  }

  Future<SemanticTextEmbedder> requireReadyEmbedder() async {
    final current = await checkReadiness();
    if (!current.isReady) {
      throw EmbeddingModelNotReadyException(current);
    }
    return _embedder ??= OnDeviceSemanticTextEmbedder(
      model: await _runtime.getActiveEmbedder(),
      modelId: selectedModelId,
    );
  }

  EmbeddingModelReadiness _setReadiness(
    EmbeddingModelReadiness readiness, {
    bool notify = true,
  }) {
    _readiness = readiness;
    if (notify) {
      notifyListeners();
    }
    return readiness;
  }

  static String _activationId(ModelDescriptor descriptor) {
    final filename = descriptor.storageFileName;
    final dot = filename.lastIndexOf('.');
    return dot <= 0 ? filename : filename.substring(0, dot);
  }
}
