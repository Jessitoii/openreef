import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/models/hugging_face_token_store.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';

void main() {
  test(
    'no selected model initializes to verified default install state',
    () async {
      final env = await _Environment.create(runtime: _FakeEmbeddingRuntime());

      await env.manager.initialize();

      expect(env.controller.settings.semanticEmbeddingModelId, 'gecko-256');
      expect(
        env.manager.readiness.status,
        EmbeddingModelReadinessStatus.downloadable,
      );
      expect(env.manager.readiness.model?.requiresHfToken, isFalse);
    },
  );

  test('ready selected model provides managed semantic embedder', () async {
    final runtime = _FakeEmbeddingRuntime(
      active: true,
      installedIds: {'gecko-256'},
    );
    final env = await _Environment.create(runtime: runtime);

    await env.manager.initialize();
    final embedder = await env.manager.requireReadyEmbedder();

    expect(env.manager.readiness.status, EmbeddingModelReadinessStatus.ready);
    expect(embedder.modelId, 'gecko-256');
    expect(await embedder.embedQuery('battery level'), isNotEmpty);
  });

  test('installed selected model is prepared on startup', () async {
    final runtime = _FakeEmbeddingRuntime(installedIds: {'gecko-512'});
    final env = await _Environment.create(
      runtime: runtime,
      selectedEmbeddingModelId: 'gecko-512',
    );

    await env.manager.initialize();

    expect(runtime.lastActivatedId, 'gecko-512');
    expect(env.manager.readiness.status, EmbeddingModelReadinessStatus.ready);
  });

  test('token-required model without token reports requires auth', () async {
    final env = await _Environment.create(runtime: _FakeEmbeddingRuntime());
    await env.manager.initialize();

    await env.manager.selectModel('embeddinggemma-300m-256');

    expect(
      env.manager.readiness.status,
      EmbeddingModelReadinessStatus.requiresAuth,
    );
    expect(env.manager.readiness.message, contains('Hugging Face token'));
  });

  test(
    'token-required model with token can install without logging token state',
    () async {
      final runtime = _FakeEmbeddingRuntime();
      final tokenStore = _MemoryTokenStore();
      final env = await _Environment.create(
        runtime: runtime,
        tokenStore: tokenStore,
      );
      await env.manager.initialize();
      await env.manager.selectModel('embeddinggemma-300m-256');

      await env.manager.saveHfToken('embeddinggemma-300m-256', 'hf_secret');
      await env.manager.installSelectedModel();

      expect(runtime.lastInstalledId, 'embeddinggemma-300m-256');
      expect(runtime.lastToken, 'hf_secret');
      expect(env.manager.readiness.status, EmbeddingModelReadinessStatus.ready);
    },
  );

  test('public Gecko model does not request Hugging Face token', () async {
    final runtime = _FakeEmbeddingRuntime();
    final env = await _Environment.create(runtime: runtime);
    await env.manager.initialize();

    await env.manager.installSelectedModel();

    expect(runtime.lastInstalledId, 'gecko-256');
    expect(runtime.lastToken, isNull);
  });

  test(
    'switching model persists selection and invalidates candidate index',
    () async {
      var invalidations = 0;
      final env = await _Environment.create(
        runtime: _FakeEmbeddingRuntime(),
        onModelChanged: () => invalidations++,
      );
      await env.manager.initialize();

      await env.manager.selectModel('gecko-512');

      expect(env.controller.settings.semanticEmbeddingModelId, 'gecko-512');
      expect(invalidations, 1);
    },
  );

  test('active embedder for different selected model is not ready', () async {
    final runtime = _FakeEmbeddingRuntime(
      active: true,
      activeId: 'Gecko_256_quant',
      installedIds: {'gecko-512'},
    );
    final env = await _Environment.create(runtime: runtime);
    await env.manager.initialize();

    await env.manager.selectModel('gecko-512');

    expect(
      env.manager.readiness.status,
      EmbeddingModelReadinessStatus.installed,
    );
  });

  test(
    'not ready manager throws typed readiness exception before embedding',
    () async {
      final env = await _Environment.create(runtime: _FakeEmbeddingRuntime());
      await env.manager.initialize();

      await expectLater(
        env.manager.requireReadyEmbedder(),
        throwsA(isA<EmbeddingModelNotReadyException>()),
      );
    },
  );
}

class _Environment {
  const _Environment({required this.controller, required this.manager});

  final SettingsController controller;
  final EmbeddingModelManager manager;

  static Future<_Environment> create({
    required _FakeEmbeddingRuntime runtime,
    _MemoryTokenStore? tokenStore,
    void Function()? onModelChanged,
    String? selectedEmbeddingModelId,
  }) async {
    final dir = await Directory.systemTemp.createTemp(
      'openreef_embedding_test_',
    );
    final controller = SettingsController(
      store: SettingsStore(
        File('${dir.path}${Platform.pathSeparator}settings.json'),
      ),
    );
    await controller.initialize();
    if (selectedEmbeddingModelId != null) {
      controller.updateSemanticEmbeddingModelId(selectedEmbeddingModelId);
    }
    final manager = EmbeddingModelManager(
      registry: const ModelRegistry(),
      settingsController: controller,
      tokenStore: tokenStore ?? _MemoryTokenStore(),
      runtime: runtime,
      onModelChanged: onModelChanged,
    );
    return _Environment(controller: controller, manager: manager);
  }
}

class _MemoryTokenStore implements HuggingFaceTokenStore {
  final Map<String, String> _tokens = <String, String>{};

  @override
  Future<void> deleteTokenForModel(String modelId) async {
    _tokens.remove(modelId);
  }

  @override
  Future<bool> hasTokenForModel(String modelId) async {
    return (_tokens[modelId] ?? '').isNotEmpty;
  }

  @override
  Future<String?> readTokenForModel(String modelId) async {
    return _tokens[modelId];
  }

  @override
  Future<void> writeTokenForModel(String modelId, String token) async {
    _tokens[modelId] = token;
  }
}

class _FakeEmbeddingRuntime implements EmbeddingModelRuntime {
  _FakeEmbeddingRuntime({
    this.active = false,
    this.activeId = 'Gecko_256_quant',
    Set<String>? installedIds,
  }) : installedIds = installedIds ?? <String>{};

  bool active;
  String? activeId;
  final Set<String> installedIds;
  String? lastInstalledId;
  String? lastActivatedId;
  String? lastToken;

  @override
  String? activeEmbedderId() => activeId;

  @override
  Future<EmbeddingModel> getActiveEmbedder() async {
    return _FakeEmbeddingModel();
  }

  @override
  bool hasActiveEmbedder() => active;

  @override
  Future<void> activateInstalled(ModelDescriptor descriptor) async {
    lastActivatedId = descriptor.id;
    active = true;
    activeId = descriptor.storageFileName.substring(
      0,
      descriptor.storageFileName.lastIndexOf('.'),
    );
  }

  @override
  Future<void> install({
    required ModelDescriptor descriptor,
    required String? hfToken,
    required void Function(double progress) onProgress,
  }) async {
    lastInstalledId = descriptor.id;
    lastToken = hfToken;
    onProgress(1);
    installedIds.add(descriptor.id);
    active = true;
    activeId = descriptor.storageFileName.substring(
      0,
      descriptor.storageFileName.lastIndexOf('.'),
    );
  }

  @override
  Future<bool> isInstalled(ModelDescriptor descriptor) async {
    return installedIds.contains(descriptor.id);
  }
}

class _FakeEmbeddingModel implements EmbeddingModel {
  @override
  Future<void> close() async {}

  @override
  Future<List<double>> generateEmbedding(
    String text, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    return taskType == TaskType.retrievalQuery
        ? <double>[1, 0, 0]
        : <double>[0, 1, 0];
  }

  @override
  Future<List<List<double>>> generateEmbeddings(
    List<String> texts, {
    TaskType taskType = TaskType.retrievalQuery,
  }) async {
    final result = <List<double>>[];
    for (final text in texts) {
      result.add(await generateEmbedding(text, taskType: taskType));
    }
    return result;
  }

  @override
  Future<int> getDimension() async => 3;
}
