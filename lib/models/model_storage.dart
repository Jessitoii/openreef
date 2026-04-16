import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:path_provider/path_provider.dart';

typedef ModelDirectoryResolver = Future<Directory> Function();
typedef ActiveDownloadChecker = Future<bool> Function(String filename);

class ModelStorage {
  ModelStorage({
    ModelDirectoryResolver? directoryResolver,
    ActiveDownloadChecker? activeDownloadChecker,
  }) : _directoryResolver = directoryResolver ?? _defaultDirectoryResolver,
       _activeDownloadChecker =
           activeDownloadChecker ?? _defaultActiveDownloadChecker;

  static const int _minimumUnknownModelSizeBytes = 1024 * 1024;
  static const String _downloadGroup = 'smart_downloads';

  final ModelDirectoryResolver _directoryResolver;
  final ActiveDownloadChecker _activeDownloadChecker;

  Future<File> _installedIndexFile() async {
    final directory = await getModelsDirectory();
    return File('${directory.path}${Platform.pathSeparator}installed.json');
  }

  Future<Directory> getModelsDirectory() async {
    final base = await _baseDirectory();
    final directory = Directory('${base.path}${Platform.pathSeparator}models');
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> _baseDirectory() async {
    final base = await _directoryResolver();
    await base.create(recursive: true);
    return base;
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

  Future<bool> isValidInstalledFile(
    ModelDescriptor descriptor, {
    File? file,
  }) async {
    final target = file ?? await getInstalledFile(descriptor);
    if (!await target.exists()) {
      return false;
    }
    final size = await target.length();
    final expected = descriptor.expectedFileSizeBytes;
    if (expected > 0) {
      return size == expected;
    }
    return size >= _minimumUnknownModelSizeBytes;
  }

  Future<InstalledModelRecord?> reconcileDescriptor(
    ModelDescriptor descriptor,
  ) async {
    final canonical = await getInstalledFile(descriptor);
    await _promoteValidLegacyFile(descriptor, canonical);

    if (await isValidInstalledFile(descriptor, file: canonical)) {
      return recoverInstalledModel(descriptor, file: canonical);
    }

    if (await canonical.exists()) {
      await canonical.delete();
    }
    final stored = await _readInstalledIndex();
    await _writeInstalledIndex(
      stored.where((entry) => entry.descriptorId != descriptor.id).toList(),
    );
    return null;
  }

  Future<List<InstalledModelRecord>> reconcileInstalledModels(
    ModelRegistry registry,
  ) async {
    final installed = <InstalledModelRecord>[];
    for (final descriptor in registry.models) {
      final record = await reconcileDescriptor(descriptor);
      if (record != null) {
        installed.add(record);
      }
    }
    await cleanupInvalidDownloadArtifacts(registry);
    installed.sort(
      (left, right) => right.installedAt.compareTo(left.installedAt),
    );
    return installed;
  }

  Future<InstalledModelRecord> recoverInstalledModel(
    ModelDescriptor descriptor, {
    File? file,
  }) async {
    final installedFile = file ?? await getInstalledFile(descriptor);
    final size = await installedFile.length();
    final stored = await _readInstalledIndex();
    final existing = stored.firstWhere(
      (entry) => entry.descriptorId == descriptor.id,
      orElse: () => _StoredInstalledModel(
        descriptorId: descriptor.id,
        modelId: descriptor.storageFileName,
        installedAt: DateTime.now(),
      ),
    );
    final record = InstalledModelRecord(
      descriptor: descriptor,
      modelId: descriptor.storageFileName,
      path: installedFile.path,
      fileSizeBytes: size,
      installedAt: existing.installedAt.millisecondsSinceEpoch == 0
          ? DateTime.now()
          : existing.installedAt,
    );
    await saveInstalledModel(record);
    return record;
  }

  Future<List<InstalledModelRecord>> listInstalledModels(
    ModelRegistry registry,
  ) async {
    await reconcileInstalledModels(registry);
    final stored = await _readInstalledIndex();
    final installed = <InstalledModelRecord>[];
    for (final entry in stored) {
      final descriptor = registry.findById(entry.descriptorId);
      if (descriptor == null) {
        continue;
      }
      final file = entry.path == null
          ? await getInstalledFile(descriptor)
          : File(entry.path!);
      if (!await isValidInstalledFile(descriptor, file: file)) {
        continue;
      }
      final size = await file.length();
      installed.add(
        InstalledModelRecord(
          descriptor: descriptor,
          modelId: descriptor.storageFileName,
          path: file.path,
          fileSizeBytes: size,
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

  Future<InstalledModelRecord?> getInstalledModelByDescriptorId(
    ModelRegistry registry,
    String descriptorId,
  ) async {
    final models = await listInstalledModels(registry);
    for (final model in models) {
      if (model.descriptor.id == descriptorId) {
        return model;
      }
    }
    return null;
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
    final updated = stored
        .where((entry) => entry.descriptorId != descriptor.id)
        .toList();
    await _writeInstalledIndex(updated);
  }

  Future<void> cleanupInvalidDownloadArtifacts(ModelRegistry registry) async {
    final base = await _baseDirectory();
    final candidates = <File>[
      for (final descriptor in registry.models)
        await getPartialFile(descriptor),
      ...await _backgroundDownloaderFiles(base),
    ];

    for (final file in candidates) {
      if (!await file.exists()) {
        continue;
      }
      final filename = _basename(file.path);
      if (await _activeDownloadChecker(filename)) {
        continue;
      }
      await file.delete();
    }
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

  Future<void> _promoteValidLegacyFile(
    ModelDescriptor descriptor,
    File canonical,
  ) async {
    if (await isValidInstalledFile(descriptor, file: canonical)) {
      await _deleteDuplicateLegacyFiles(descriptor, canonical);
      return;
    }

    final legacyFile = await _findValidLegacyFile(descriptor, canonical);
    if (legacyFile == null) {
      return;
    }

    await canonical.parent.create(recursive: true);
    if (await canonical.exists()) {
      await canonical.delete();
    }
    try {
      await legacyFile.rename(canonical.path);
    } on FileSystemException {
      await legacyFile.copy(canonical.path);
      await legacyFile.delete();
    }
  }

  Future<File?> _findValidLegacyFile(
    ModelDescriptor descriptor,
    File canonical,
  ) async {
    for (final file in await _legacyCandidates(descriptor, canonical)) {
      if (await isValidInstalledFile(descriptor, file: file)) {
        return file;
      }
    }
    return null;
  }

  Future<void> _deleteDuplicateLegacyFiles(
    ModelDescriptor descriptor,
    File canonical,
  ) async {
    for (final file in await _legacyCandidates(descriptor, canonical)) {
      if (file.path == canonical.path || !await file.exists()) {
        continue;
      }
      if (await isValidInstalledFile(descriptor, file: file)) {
        await file.delete();
      }
    }
  }

  Future<List<File>> _legacyCandidates(
    ModelDescriptor descriptor,
    File canonical,
  ) async {
    final base = await _baseDirectory();
    final names = <String>{
      descriptor.storageFileName,
      _urlFilename(descriptor.downloadUrl),
    };
    return <File>[
      for (final name in names)
        if (name.isNotEmpty) File('${base.path}${Platform.pathSeparator}$name'),
      for (final name in names)
        if (name.isNotEmpty)
          File('${canonical.parent.path}${Platform.pathSeparator}$name'),
    ];
  }

  Future<List<File>> _backgroundDownloaderFiles(Directory base) async {
    final candidates = <File>[];
    final filesDirectory = Directory(
      '${base.parent.path}${Platform.pathSeparator}files',
    );
    if (!await filesDirectory.exists()) {
      return candidates;
    }
    await for (final entity in filesDirectory.list()) {
      if (entity is File &&
          _basename(
            entity.path,
          ).startsWith('com.bbflight.background_downloader')) {
        candidates.add(entity);
      }
    }
    return candidates;
  }

  static Future<bool> _defaultActiveDownloadChecker(String filename) async {
    try {
      final downloader = FileDownloader();
      final active = await downloader.allTasks(
        group: _downloadGroup,
        includeTasksWaitingToRetry: true,
      );
      if (active.any((task) => task.filename == filename)) {
        return true;
      }
      final records = await downloader.database.allRecords();
      return records.any(
        (record) =>
            record.task.filename == filename &&
            record.status != TaskStatus.complete,
      );
    } on Object {
      return false;
    }
  }

  String _urlFilename(String url) {
    return Uri.tryParse(url)?.pathSegments.last ?? '';
  }

  String _basename(String path) {
    final separator = Platform.pathSeparator;
    final index = path.lastIndexOf(separator);
    return index == -1 ? path : path.substring(index + 1);
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
      installedAt:
          DateTime.tryParse(json['installedAt'] as String? ?? '') ??
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
