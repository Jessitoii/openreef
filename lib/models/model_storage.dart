import 'dart:convert';
import 'dart:io';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter/services.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:path_provider/path_provider.dart';

typedef ModelDirectoryResolver = Future<Directory> Function();

class ModelStorage {
  ModelStorage({ModelDirectoryResolver? directoryResolver})
    : _directoryResolver = directoryResolver ?? _defaultDirectoryResolver;

  final ModelDirectoryResolver _directoryResolver;

  Future<File> _installedIndexFile() async {
    final directory = await getModelsDirectory();
    return File('${directory.path}${Platform.pathSeparator}installed.json');
  }

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
    List<String> installedIds = <String>[];
    try {
      installedIds = await FlutterGemma.listInstalledModels();
    } on MissingPluginException {
      installedIds = <String>[];
    }
    final stored = await _readInstalledIndex();
    final installed = <InstalledModelRecord>[];
    for (final entry in stored) {
      final descriptor = registry.findById(entry.descriptorId);
      if (descriptor == null) {
        continue;
      }
      if (!installedIds.contains(entry.modelId)) {
        continue;
      }
      installed.add(
        InstalledModelRecord(
          descriptor: descriptor,
          modelId: entry.modelId,
          path: entry.path,
          fileSizeBytes:
              entry.fileSizeBytes ?? descriptor.expectedFileSizeBytes,
          installedAt: entry.installedAt,
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
    final stored = await _readInstalledIndex();
    final removed = stored.firstWhere(
      (entry) => entry.descriptorId == descriptor.id,
      orElse: () => _StoredInstalledModel(
        descriptorId: descriptor.id,
        modelId: '',
        installedAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    );
    if (removed.modelId.isNotEmpty) {
      try {
        await FlutterGemma.uninstallModel(removed.modelId);
      } on Exception {
        // Ignore missing model entries during cleanup.
      }
    }
    final updated =
        stored.where((entry) => entry.descriptorId != descriptor.id).toList();
    await _writeInstalledIndex(updated);
  }

  Future<void> saveInstalledModel(InstalledModelRecord record) async {
    final stored = await _readInstalledIndex();
    final updated = <_StoredInstalledModel>[
      for (final entry in stored)
        if (entry.descriptorId != record.descriptor.id) entry,
      _StoredInstalledModel(
        descriptorId: record.descriptor.id,
        modelId: record.modelId,
        path: record.path,
        fileSizeBytes: record.fileSizeBytes,
        installedAt: record.installedAt,
      ),
    ];
    await _writeInstalledIndex(updated);
  }

  static Future<Directory> _defaultDirectoryResolver() {
    return getApplicationDocumentsDirectory();
  }

  Future<List<_StoredInstalledModel>> _readInstalledIndex() async {
    final file = await _installedIndexFile();
    if (!await file.exists()) {
      return <_StoredInstalledModel>[];
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return <_StoredInstalledModel>[];
    }
    final decoded = jsonDecode(content);
    if (decoded is! List) {
      return <_StoredInstalledModel>[];
    }
    return decoded
        .whereType<Map<String, Object?>>()
        .map(_StoredInstalledModel.fromJson)
        .toList();
  }

  Future<void> _writeInstalledIndex(List<_StoredInstalledModel> entries) async {
    final file = await _installedIndexFile();
    final encoded = jsonEncode(entries.map((entry) => entry.toJson()).toList());
    await file.writeAsString(encoded, flush: true);
  }
}

class _StoredInstalledModel {
  _StoredInstalledModel({
    required this.descriptorId,
    required this.modelId,
    required this.installedAt,
    this.path,
    this.fileSizeBytes,
  });

  final String descriptorId;
  final String modelId;
  final String? path;
  final int? fileSizeBytes;
  final DateTime installedAt;

  factory _StoredInstalledModel.fromJson(Map<String, Object?> json) {
    return _StoredInstalledModel(
      descriptorId: json['descriptorId'] as String? ?? '',
      modelId: json['modelId'] as String? ?? '',
      path: json['path'] as String?,
      fileSizeBytes: json['fileSizeBytes'] as int?,
      installedAt: DateTime.tryParse(json['installedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'descriptorId': descriptorId,
      'modelId': modelId,
      'path': path,
      'fileSizeBytes': fileSizeBytes,
      'installedAt': installedAt.toIso8601String(),
    };
  }
}
