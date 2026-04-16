import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
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
      models: <ModelDescriptor>[_primary, _secondary],
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

  test('loads device stats and picks a compatible default model', () async {
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
    );

    await controller.initialize();

    expect(controller.state.deviceStats?.freeRam, 2.0);
    expect(controller.state.selectedModel?.id, _primary.id);
    expect(settingsController.settings.generationModelId, _primary.id);
  });

  test('fresh install downloads and emits installed state', () async {
    final downloader = _FakeModelDownloader(
      storage: storage,
      onDownload: (model, onProgress) async {
        expect(model.id, _primary.id);
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
    final installed = await controller.startDownload();

    expect(installed, isNotNull);
    expect(downloader.downloadCount, 1);
    expect(controller.state.status, ModelDownloadStatus.completed);
    expect(controller.state.progress, 1);
    expect(controller.state.installedModel?.descriptor.id, _primary.id);
    expect(settingsController.settings.generationModelId, _primary.id);
  });

  test(
    'existing file plus missing metadata initializes as installed',
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
      final installed = await controller.startDownload();

      expect(installed, isNotNull);
      expect(downloader.downloadCount, 0);
      expect(controller.state.status, ModelDownloadStatus.completed);
      expect(controller.state.progress, 1);
    },
  );

  test(
    'completion keeps UI state installed instead of reset to download',
    () async {
      final downloader = _FakeModelDownloader(
        storage: storage,
        onDownload: (model, onProgress) async {
          final file = await storage.getInstalledFile(model);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
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
      );

      await controller.initialize();
      await controller.startDownload();

      expect(controller.state.status, ModelDownloadStatus.completed);
      expect(controller.state.installedRecordFor(_primary), isNotNull);
      expect(controller.isInstalled(_primary), isTrue);
      expect(controller.isActive(_primary), isTrue);
    },
  );

  test('installed active model survives controller restart', () async {
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
    expect(controller.isActive(_primary), isTrue);
  });

  test('stale metadata missing file reloads as not installed', () async {
    await storage.saveInstalledModel(
      InstalledModelRecord(
        descriptor: _primary,
        modelId: _primary.storageFileName,
        fileSizeBytes: 4,
        installedAt: DateTime.now(),
      ),
    );
    final controller = _controller(
      registry: registry,
      storage: storage,
      settingsController: settingsController,
    );

    await controller.initialize();

    expect(controller.state.installedModel, isNull);
    expect(controller.isInstalled(_primary), isFalse);
    expect(controller.state.status, ModelDownloadStatus.idle);
  });

  test(
    'installed inactive selected model activates without download',
    () async {
      final primary = await storage.getInstalledFile(_primary);
      await primary.parent.create(recursive: true);
      await primary.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      await storage.recoverInstalledModel(_primary, file: primary);
      final secondary = await storage.getInstalledFile(_secondary);
      await secondary.writeAsBytes(<int>[5, 6], flush: true);
      await storage.recoverInstalledModel(_secondary, file: secondary);
      settingsController.updateGenerationModelId(_primary.id);
      final downloader = _FakeModelDownloader(storage: storage);
      final controller = _controller(
        registry: registry,
        storage: storage,
        settingsController: settingsController,
        downloader: downloader,
      );

      await controller.initialize();
      controller.selectModel(_secondary);
      expect(controller.isInstalled(_secondary), isTrue);
      expect(controller.isActive(_secondary), isFalse);
      await controller.activateSelectedModel();

      expect(downloader.downloadCount, 0);
      expect(controller.isActive(_secondary), isTrue);
      expect(settingsController.settings.generationModelId, _secondary.id);
    },
  );
}

ModelDownloadController _controller({
  required ModelRegistry registry,
  required ModelStorage storage,
  required SettingsController settingsController,
  ModelDownloader? downloader,
}) {
  return ModelDownloadController(
    registry: registry,
    storage: storage,
    downloader: downloader ?? _FakeModelDownloader(storage: storage),
    bridge: _FakeLiteRtBridge(),
    settingsController: settingsController,
  );
}

class _FakeModelDownloader extends ModelDownloader {
  _FakeModelDownloader({required super.storage, this.onDownload})
    : super(
        registerInstalledFile: (descriptor, file) async =>
            descriptor.storageFileName,
      );

  int downloadCount = 0;

  final Future<ModelDownloadResult> Function(
    ModelDescriptor descriptor,
    void Function(int downloadedBytes, int totalBytes) onProgress,
  )?
  onDownload;

  @override
  Future<ModelDownloadResult> download({
    required ModelDescriptor descriptor,
    required void Function(int downloadedBytes, int totalBytes) onProgress,
  }) async {
    downloadCount += 1;
    if (onDownload != null) {
      return onDownload!(descriptor, onProgress);
    }
    return const ModelDownloadResult(
      status: ModelDownloadResultStatus.cancelled,
    );
  }
}

class _FakeLiteRtBridge extends LiteRtBridge {
  @override
  Future<LiteRtDeviceStats> getDeviceStats() async {
    return const LiteRtDeviceStats(freeRam: 2.0, npuReady: false);
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
