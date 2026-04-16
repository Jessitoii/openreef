import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';

void main() {
  late Directory tempRoot;
  late Directory documentsDirectory;
  late ModelStorage storage;
  late ModelRegistry registry;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('openreef-models-');
    documentsDirectory = Directory(
      '${tempRoot.path}${Platform.pathSeparator}app_flutter',
    );
    storage = ModelStorage(
      directoryResolver: () async => documentsDirectory,
      activeDownloadChecker: (_) async => false,
    );
    registry = ModelRegistry(models: <ModelDescriptor>[_primary, _secondary]);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('reconciles existing canonical file without metadata', () async {
    final file = await storage.getInstalledFile(_primary);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[1, 2, 3, 4], flush: true);

    final installedModels = await storage.listInstalledModels(registry);

    expect(installedModels, hasLength(1));
    expect(installedModels.first.descriptor.id, _primary.id);
    expect(installedModels.first.modelId, _primary.storageFileName);
    expect(installedModels.first.path, file.path);
  });

  test(
    'looks up installed model by descriptor id after reconciliation',
    () async {
      final older = await storage.getInstalledFile(_primary);
      await older.parent.create(recursive: true);
      await older.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      final newer = await storage.getInstalledFile(_secondary);
      await newer.writeAsBytes(<int>[5, 6], flush: true);

      final installed = await storage.getInstalledModelByDescriptorId(
        registry,
        _primary.id,
      );

      expect(installed, isNotNull);
      expect(installed!.descriptor.id, _primary.id);
    },
  );

  test(
    'stale metadata with missing file is corrected to not installed',
    () async {
      await storage.saveInstalledModel(
        InstalledModelRecord(
          descriptor: _primary,
          modelId: _primary.storageFileName,
          fileSizeBytes: 4,
          installedAt: DateTime.now(),
        ),
      );

      final installedModels = await storage.listInstalledModels(registry);

      expect(installedModels, isEmpty);
    },
  );

  test('truncated file does not count as installed', () async {
    final file = await storage.getInstalledFile(_primary);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[1, 2, 3], flush: true);

    final installedModels = await storage.listInstalledModels(registry);

    expect(installedModels, isEmpty);
    expect(await file.exists(), isFalse);
  });

  test('legacy root file is moved into canonical models directory', () async {
    await documentsDirectory.create(recursive: true);
    final legacy = File(
      '${documentsDirectory.path}${Platform.pathSeparator}${_primary.storageFileName}',
    );
    await legacy.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
    final canonical = await storage.getInstalledFile(_primary);

    final installed = await storage.reconcileDescriptor(_primary);

    expect(installed, isNotNull);
    expect(await legacy.exists(), isFalse);
    expect(await canonical.exists(), isTrue);
    expect(installed!.path, canonical.path);
  });

  test(
    'orphaned downloader fragments are deleted but canonical file remains',
    () async {
      final canonical = await storage.getInstalledFile(_primary);
      await canonical.parent.create(recursive: true);
      await canonical.writeAsBytes(<int>[1, 2, 3, 4], flush: true);
      final filesDirectory = Directory(
        '${tempRoot.path}${Platform.pathSeparator}files',
      );
      await filesDirectory.create(recursive: true);
      final orphan = File(
        '${filesDirectory.path}${Platform.pathSeparator}com.bbflight.background_downloader-test',
      );
      await orphan.writeAsBytes(<int>[1, 2], flush: true);

      final installedModels = await storage.reconcileInstalledModels(registry);

      expect(installedModels, hasLength(1));
      expect(await canonical.exists(), isTrue);
      expect(await orphan.exists(), isFalse);
    },
  );
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
