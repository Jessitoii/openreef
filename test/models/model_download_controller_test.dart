import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/hugging_face_token_store.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_download_state.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/settings/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDirectory;
  late ModelStorage storage;
  late SettingsController settingsController;
  late ModelRegistry registry;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openreef-controller-',
    );
    storage = ModelStorage(
      directoryResolver: () async => tempDirectory,
      activeDownloadChecker: (_) async => false,
    );
    settingsController = SettingsController(
      store: SettingsStore(
        File('${tempDirectory.path}${Platform.pathSeparator}settings.json'),
      ),
    );
    await settingsController.initialize();
    registry = const ModelRegistry(
      models: <ModelDescriptor>[_primary, _secondary, _gated],
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      for (var attempt = 0; attempt < 5; attempt += 1) {
        try {
          await tempDirectory.delete(recursive: true);
          break;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    }
  });

  test('loads device stats without selecting an active model', () async {
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
    );

    await controller.initialize();

    expect(controller.state.deviceStats?.freeRam, 2.0);
    expect(controller.state.selectedModel?.id, _primary.id);
    expect(settingsController.settings.generationModelId, isNull);
  });

  test('download creates installed record but does not mark active', () async {
    final downloader = _FakeModelDownloader(
      storage: storage,
      onDownload: (model, onProgress, authToken) async {
        expect(model.id, _primary.id);
        expect(authToken, isNull);
        onProgress(2, 4);
        final file = await storage.getInstalledFile(model);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
        final record = await storage.recoverInstalledModel(model, file: file);
        onProgress(4, 4);
        return ModelDownloadResult(
          status: ModelDownloadResultStatus.completed,
          installedModel: record,
        );
      },
    );
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
      downloader: downloader,
    );

    await controller.initialize();
    final installed = await controller.downloadSelectedModel();

    expect(installed, isNotNull);
    expect(downloader.downloadCount, 1);
    expect(controller.state.status, ModelDownloadStatus.completed);
    expect(controller.state.progress, 1);
    expect(controller.state.installedModel?.descriptor.id, _primary.id);
    expect(
      controller.cardStateFor(_primary).lifecycle,
      ModelCardLifecycle.downloaded,
    );
    expect(settingsController.settings.generationModelId, isNull);
    expect(controller.isActive(_primary), isFalse);
  });

  test(
    'existing file plus missing metadata initializes as downloaded',
    () async {
      final file = await storage.getInstalledFile(_primary);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      final controller = _controller(
        registry: registry,
        storage: storage,
        settingsController: settingsController,
      );

      await controller.initialize();

      expect(controller.state.status, ModelDownloadStatus.completed);
      expect(controller.state.installedModel?.descriptor.id, _primary.id);
      expect(controller.isInstalled(_primary), isTrue);
      expect(controller.cardStateFor(_primary).primaryLabel, 'Initialize');
    },
  );

  test(
    'existing file plus download tap does not start duplicate download',
    () async {
      final file = await storage.getInstalledFile(_primary);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      final downloader = _FakeModelDownloader(storage: storage);
      final controller = _controller(
        registry: registry,
        storage: storage,
        settingsController: settingsController,
        downloader: downloader,
      );

      await controller.initialize();
      final installed = await controller.downloadSelectedModel();

      expect(installed, isNotNull);
      expect(downloader.downloadCount, 0);
      expect(controller.state.status, ModelDownloadStatus.completed);
      expect(controller.state.progress, 1);
      expect(settingsController.settings.generationModelId, isNull);
    },
  );

  test(
    'initialization projects initialized only after LiteRT success',
    () async {
      final bridge = _FakeLiteRtBridge();
      final file = await storage.getInstalledFile(_primary);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await storage.recoverInstalledModel(_primary, file: file);
      final controller = _controller(
        registry: registry,
        storage: storage,
        settingsController: settingsController,
        bridge: bridge,
      );

      await controller.initialize();
      final initialized = await controller.initializeSelectedModel();

      expect(initialized, isNotNull);
      expect(bridge.initializedPaths, <String>[_primary.storageFileName]);
      expect(
        controller.cardStateFor(_primary).lifecycle,
        ModelCardLifecycle.initialized,
      );
      expect(settingsController.settings.generationModelId, isNull);
    },
  );

  test('activation is blocked before initialization', () async {
    final file = await storage.getInstalledFile(_primary);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    await storage.recoverInstalledModel(_primary, file: file);
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
    );

    await controller.initialize();
    final active = await controller.activateSelectedModel();

    expect(active, isNull);
    expect(
      controller.state.errorMessage,
      'Initialize this model before making it active.',
    );
    expect(settingsController.settings.generationModelId, isNull);
    expect(controller.isActive(_primary), isFalse);
  });

  test('activation updates settings only after initialization', () async {
    final bridge = _FakeLiteRtBridge();
    final primary = await storage.getInstalledFile(_primary);
    await primary.parent.create(recursive: true);
    await primary.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    await storage.recoverInstalledModel(_primary, file: primary);
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
      bridge: bridge,
    );

    await controller.initialize();
    await controller.initializeSelectedModel();
    final active = await controller.activateSelectedModel();

    expect(active, isNotNull);
    expect(settingsController.settings.generationModelId, _primary.id);
    expect(
      controller.cardStateFor(_primary).lifecycle,
      ModelCardLifecycle.active,
    );
  });

  test(
    'runtime initialization failure projects failedInitialization',
    () async {
      final file = await storage.getInstalledFile(_primary);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await storage.recoverInstalledModel(_primary, file: file);
      final controller = _controller(
        registry: registry,
        storage: storage,
        settingsController: settingsController,
        bridge: _FakeLiteRtBridge(initFailure: StateError('boom')),
      );

      await controller.initialize();
      final initialized = await controller.initializeSelectedModel();

      expect(initialized, isNull);
      expect(
        controller.cardStateFor(_primary).lifecycle,
        ModelCardLifecycle.failedInitialization,
      );
      expect(settingsController.settings.generationModelId, isNull);
    },
  );

  test(
    'restart with downloaded but uninitialized model is not active',
    () async {
      final file = await storage.getInstalledFile(_primary);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await storage.recoverInstalledModel(_primary, file: file);
      settingsController.updateGenerationModelId(_primary.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final restartedSettings = SettingsController(
        store: SettingsStore(
          File('${tempDirectory.path}${Platform.pathSeparator}settings.json'),
        ),
      );
      await restartedSettings.initialize();
      final controller = _controller(
        registry: registry,
        storage: storage,
        settingsController: restartedSettings,
      );

      await controller.initialize();

      expect(controller.state.installedModel?.descriptor.id, _primary.id);
      expect(
        controller.cardStateFor(_primary).lifecycle,
        ModelCardLifecycle.downloaded,
      );
      expect(controller.isActive(_primary), isFalse);
    },
  );

  test(
    'restart active model is active only after bootstrap marks initialized',
    () async {
      final file = await storage.getInstalledFile(_primary);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await storage.recoverInstalledModel(_primary, file: file);
      settingsController.updateGenerationModelId(_primary.id);
      final controller = _controller(
        registry: registry,
        storage: storage,
        settingsController: settingsController,
      );

      await controller.initialize();
      expect(controller.isActive(_primary), isFalse);

      controller.markInitializedModel(_primary.storageFileName);

      expect(
        controller.cardStateFor(_primary).lifecycle,
        ModelCardLifecycle.active,
      );
    },
  );

  test('missing HF token blocks gated download', () async {
    final tokenStore = _FakeHuggingFaceTokenStore();
    final downloader = _FakeModelDownloader(storage: storage);
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
      downloader: downloader,
      tokenStore: tokenStore,
    );

    await controller.initialize();
    controller.selectModel(_gated);
    final installed = await controller.downloadSelectedModel();

    expect(installed, isNull);
    expect(downloader.downloadCount, 0);
    expect(
      controller.cardStateFor(_gated).lifecycle,
      ModelCardLifecycle.missingToken,
    );
  });

  test('present HF token is passed to gated download', () async {
    final tokenStore = _FakeHuggingFaceTokenStore(token: 'hf_test');
    final downloader = _FakeModelDownloader(
      storage: storage,
      onDownload: (model, onProgress, authToken) async {
        final file = await storage.getInstalledFile(model);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(<int>[1, 2, 3], flush: true);
        return ModelDownloadResult(
          status: ModelDownloadResultStatus.completed,
          installedModel: await storage.recoverInstalledModel(
            model,
            file: file,
          ),
        );
      },
    );
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
      downloader: downloader,
      tokenStore: tokenStore,
    );

    await controller.initialize();
    controller.selectModel(_gated);
    await controller.downloadSelectedModel();

    expect(downloader.lastAuthToken, 'hf_test');
  });

  test('unsupported RAM state disables primary action', () async {
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
      bridge: _FakeLiteRtBridge(freeRam: 0.5),
    );

    await controller.initialize();

    final card = controller.cardStateFor(_primary);
    expect(card.lifecycle, ModelCardLifecycle.unsupported);
    expect(card.canRunPrimaryAction, isFalse);
    expect(card.primaryLabel, 'Unavailable');
  });
}

ModelDownloadController _controller({
  required ModelRegistry registry,
  required ModelStorage storage,
  required SettingsController settingsController,
  ModelDownloader? downloader,
  _FakeLiteRtBridge? bridge,
  HuggingFaceTokenStore? tokenStore,
}) {
  return ModelDownloadController(
    registry: registry,
    storage: storage,
    downloader: downloader ?? _FakeModelDownloader(storage: storage),
    bridge: bridge ?? _FakeLiteRtBridge(),
    settingsController: settingsController,
    hfTokenStore: tokenStore,
  );
}

class _FakeModelDownloader extends ModelDownloader {
  _FakeModelDownloader({required super.storage, this.onDownload})
    : super(
        registerInstalledFile: (descriptor, file) async =>
            descriptor.storageFileName,
      );

  int downloadCount = 0;
  String? lastAuthToken;

  final Future<ModelDownloadResult> Function(
    ModelDescriptor descriptor,
    void Function(int downloadedBytes, int totalBytes) onProgress,
    String? authToken,
  )?
  onDownload;

  @override
  Future<ModelDownloadResult> download({
    required ModelDescriptor descriptor,
    required void Function(int downloadedBytes, int totalBytes) onProgress,
    String? authToken,
  }) async {
    downloadCount += 1;
    lastAuthToken = authToken;
    if (onDownload != null) {
      return onDownload!(descriptor, onProgress, authToken);
    }
    return const ModelDownloadResult(
      status: ModelDownloadResultStatus.cancelled,
    );
  }
}

class _FakeLiteRtBridge extends LiteRtBridge {
  _FakeLiteRtBridge({this.initFailure, this.freeRam = 2.0});

  final Object? initFailure;
  final double freeRam;
  final List<String> initializedPaths = <String>[];
  String? _activeModelId;

  @override
  String? get activeModelId => _activeModelId;

  @override
  Future<LiteRtDeviceStats> getDeviceStats() async {
    return LiteRtDeviceStats(freeRam: freeRam, npuReady: false);
  }

  @override
  Future<bool> initModel({required String path, required bool useNpu}) async {
    final failure = initFailure;
    if (failure != null) {
      throw failure;
    }
    initializedPaths.add(path);
    _activeModelId = path;
    return true;
  }
}

class _FakeHuggingFaceTokenStore implements HuggingFaceTokenStore {
  _FakeHuggingFaceTokenStore({this.token});

  String? token;

  @override
  Future<void> deleteTokenForModel(String modelId) async {
    token = null;
  }

  @override
  Future<bool> hasTokenForModel(String modelId) async =>
      token?.trim().isNotEmpty ?? false;

  @override
  Future<String?> readTokenForModel(String modelId) async => token;

  @override
  Future<void> writeTokenForModel(String modelId, String token) async {
    this.token = token;
  }
}

const _primary = ModelDescriptor(
  id: 'test-primary',
  name: 'Test Primary',
  downloadUrl: 'https://example.com/test-primary.litertlm',
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.litertlm,
  storageFileName: 'test-primary.litertlm',
  expectedFileSizeBytes: 4,
  contextWindow: 4096,
  minRamGb: 1,
  bestFor: 'Testing.',
  recommended: true,
);

const _secondary = ModelDescriptor(
  id: 'test-secondary',
  name: 'Test Secondary',
  downloadUrl: 'https://example.com/test-secondary.litertlm',
  modelType: ModelType.functionGemma,
  fileType: ModelFileType.litertlm,
  storageFileName: 'test-secondary.litertlm',
  expectedFileSizeBytes: 2,
  contextWindow: 4096,
  minRamGb: 1,
  bestFor: 'Testing.',
);

const _gated = ModelDescriptor(
  id: 'test-gated',
  name: 'Test Gated',
  downloadUrl: 'https://huggingface.co/example/test-gated',
  modelType: ModelType.gemmaIt,
  fileType: ModelFileType.litertlm,
  storageFileName: 'test-gated.litertlm',
  expectedFileSizeBytes: 3,
  contextWindow: 4096,
  minRamGb: 1,
  bestFor: 'Testing gated downloads.',
  requiresHfToken: true,
);
