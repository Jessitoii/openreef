import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_download_state.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methodChannel = MethodChannel('openreef/litert_channel');
  late Directory tempDirectory;
  late ModelStorage storage;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'openreef-controller-',
    );
    storage = ModelStorage(directoryResolver: () async => tempDirectory);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall call) async {
          if (call.method == 'getDeviceStats') {
            return <String, Object?>{'freeram': 2.0, 'npu_ready': false};
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('loads device stats and picks a compatible default model', () async {
    final controller = ModelDownloadController(
      registry: const ModelRegistry(),
      storage: storage,
      downloader: _FakeModelDownloader(storage: storage),
      bridge: LiteRtBridge(methodChannel: methodChannel),
    );

    await controller.initialize();

    expect(controller.state.deviceStats?.freeRam, 2.0);
    expect(controller.state.selectedModel?.id, 'gemma-3-1b-it');
  });

  test('transitions through progress and completion states', () async {
    final descriptor = const ModelRegistry().findById('gemma-3-1b-it')!;
    final installedFile = await storage.getInstalledFile(descriptor);
    await installedFile.parent.create(recursive: true);
    await installedFile.writeAsString('done');

    final downloader = _FakeModelDownloader(
      storage: storage,
      onDownload: (model, onProgress) async {
        onProgress(256, 1024);
        onProgress(1024, 1024);
        return ModelDownloadResult(
          status: ModelDownloadResultStatus.completed,
          installedModel: InstalledModelRecord(
            descriptor: descriptor,
            path: installedFile.path,
            fileSizeBytes: 1024,
            installedAt: DateTime.now(),
          ),
        );
      },
    );

    final controller = ModelDownloadController(
      registry: const ModelRegistry(),
      storage: storage,
      downloader: downloader,
      bridge: LiteRtBridge(methodChannel: methodChannel),
    );

    await controller.initialize();
    controller.selectModel(descriptor);
    final installed = await controller.startDownload();

    expect(installed, isNotNull);
    expect(controller.state.status, ModelDownloadStatus.completed);
    expect(controller.state.downloadedBytes, 1024);
  });
}

class _FakeModelDownloader extends ModelDownloader {
  _FakeModelDownloader({required super.storage, this.onDownload});

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
    if (onDownload != null) {
      return onDownload!(descriptor, onProgress);
    }
    return const ModelDownloadResult(
      status: ModelDownloadResultStatus.cancelled,
    );
  }
}
