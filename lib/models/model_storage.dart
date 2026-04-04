import 'dart:io';

import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:path_provider/path_provider.dart';

typedef ModelDirectoryResolver = Future<Directory> Function();

class ModelStorage {
  ModelStorage({ModelDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? _defaultDirectoryResolver;

  final ModelDirectoryResolver _directoryResolver;

  Future<Directory> getModelsDirectory() async {
    final base = await _directoryResolver();
    final directory = Directory('${base.path}${Platform.pathSeparator}models');
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> getInstalledFile(ModelDescriptor descriptor) async {
    final directory = await getModelsDirectory();
    return File(
      '${directory.path}${Platform.pathSeparator}${descriptor.storageFileName}',
    );
  }

  Future<File> getPartialFile(ModelDescriptor descriptor) async {
    final installed = await getInstalledFile(descriptor);
    return File('${installed.path}.part');
  }

  Future<List<InstalledModelRecord>> listInstalledModels(
    ModelRegistry registry,
  ) async {
    final installed = <InstalledModelRecord>[];
    for (final descriptor in registry.models) {
      final file = await getInstalledFile(descriptor);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      installed.add(
        InstalledModelRecord(
          descriptor: descriptor,
          path: file.path,
          fileSizeBytes: stat.size,
          installedAt: stat.modified,
        ),
      );
    }
    installed.sort(
      (left, right) => right.installedAt.compareTo(left.installedAt),
    );
    return installed;
  }

  Future<InstalledModelRecord?> getActiveInstalledModel(
    ModelRegistry registry,
  ) async {
    final models = await listInstalledModels(registry);
    if (models.isEmpty) {
      return null;
    }
    return models.first;
  }

  Future<int> getPartialBytes(ModelDescriptor descriptor) async {
    final partial = await getPartialFile(descriptor);
    if (!await partial.exists()) {
      return 0;
    }
    return partial.length();
  }

  Future<void> clearPartial(ModelDescriptor descriptor) async {
    final partial = await getPartialFile(descriptor);
    if (await partial.exists()) {
      await partial.delete();
    }
  }

  Future<void> clearInstalled(ModelDescriptor descriptor) async {
    final file = await getInstalledFile(descriptor);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<Directory> _defaultDirectoryResolver() {
    return getApplicationDocumentsDirectory();
  }
}
