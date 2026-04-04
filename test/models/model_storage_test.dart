import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';

void main() {
  late Directory tempDirectory;
  late ModelStorage storage;
  const registry = ModelRegistry();

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('openreef-models-');
    storage = ModelStorage(directoryResolver: () async => tempDirectory);
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('lists installed models and ignores missing entries', () async {
    final gemma = registry.findById('gemma-4-e2b-it')!;
    final phi = registry.findById('phi-4-mini-it')!;

    final gemmaFile = await storage.getInstalledFile(gemma);
    await gemmaFile.writeAsString('gemma');

    final partial = await storage.getPartialFile(phi);
    await partial.writeAsString('partial');

    final installedModels = await storage.listInstalledModels(registry);

    expect(installedModels, hasLength(1));
    expect(installedModels.first.descriptor.id, gemma.id);
  });

  test('returns newest installed model as active', () async {
    final older = registry.findById('gemma-3-1b-it')!;
    final newer = registry.findById('phi-4-mini-it')!;

    final olderFile = await storage.getInstalledFile(older);
    await olderFile.writeAsString('old');
    final newerFile = await storage.getInstalledFile(newer);
    await newerFile.writeAsString('new');

    final olderTime = DateTime.now().subtract(const Duration(hours: 1));
    final newerTime = DateTime.now();
    await olderFile.setLastModified(olderTime);
    await newerFile.setLastModified(newerTime);

    final active = await storage.getActiveInstalledModel(registry);

    expect(active, isNotNull);
    expect(active!.descriptor.id, newer.id);
  });
}
