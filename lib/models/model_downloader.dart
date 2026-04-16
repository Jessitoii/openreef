import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_storage.dart';

enum ModelDownloadResultStatus { completed, paused, cancelled }

typedef ModelFileRegistrar =
    Future<String> Function(ModelDescriptor descriptor, File file);

class ModelDownloadResult {
  const ModelDownloadResult({required this.status, this.installedModel});

  final ModelDownloadResultStatus status;
  final InstalledModelRecord? installedModel;
}

class ModelDownloader {
  ModelDownloader({
    required ModelStorage storage,
    ModelFileRegistrar? registerInstalledFile,
  }) : _storage = storage,
       _registerInstalledFile =
           registerInstalledFile ?? _registerInstalledFileWithFlutterGemma;

  static const String _downloadGroup = 'smart_downloads';
  static bool _androidDownloadNotificationsConfigured = false;

  final ModelStorage _storage;
  final ModelFileRegistrar _registerInstalledFile;
  CancelToken? _activeCancelToken;
  String? _activeTaskId;
  bool _pauseRequested = false;
  bool _cancelRequested = false;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

  Future<InstalledModelRecord> registerInstalledModel(
    InstalledModelRecord record,
  ) async {
    final path = record.path;
    if (path == null) {
      throw StateError('Installed model ${record.descriptor.id} has no path.');
    }
    final file = File(path);
    final modelId = await _registerInstalledFile(record.descriptor, file);
    final updated = InstalledModelRecord(
      descriptor: record.descriptor,
      modelId: modelId,
      path: file.path,
      fileSizeBytes: record.fileSizeBytes,
      installedAt: record.installedAt,
    );
    await _storage.saveInstalledModel(updated);
    return updated;
  }

  Future<void> _ensureAndroidForegroundNotificationsConfigured() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    if (_androidDownloadNotificationsConfigured) {
      return;
    }

    FileDownloader().configureNotificationForGroup(
      _downloadGroup,
      running: const TaskNotification(
        'Downloading model',
        '{filename} - {progress}% ({networkSpeed}, {timeRemaining})',
      ),
      complete: const TaskNotification(
        'Model download complete',
        '{filename} is ready to initialize.',
      ),
      error: const TaskNotification(
        'Model download failed',
        '{filename} could not be downloaded.',
      ),
      paused: const TaskNotification(
        'Model download paused',
        '{filename} is waiting to resume.',
      ),
      canceled: const TaskNotification(
        'Model download canceled',
        '{filename} was canceled.',
      ),
      progressBar: true,
    );
    _androidDownloadNotificationsConfigured = true;
    debugPrint(
      'ModelDownloader: configured Android notifications for group=$_downloadGroup',
    );
  }

  void resetStuckDownload() {
    _activeCancelToken?.cancel();
    final activeTaskId = _activeTaskId;
    if (activeTaskId != null) {
      unawaited(FileDownloader().cancelTaskWithId(activeTaskId));
    }
    _activeCancelToken = null;
    _activeTaskId = null;
    _pauseRequested = false;
    _cancelRequested = false;
    _isDownloading = false;
    debugPrint(
      'ModelDownloader.resetStuckDownload: cleared stale download state',
    );
  }

  Future<ModelDownloadResult> download({
    required ModelDescriptor descriptor,
    required void Function(int downloadedBytes, int totalBytes) onProgress,
  }) async {
    if (_isDownloading) {
      throw StateError('A model download is already in progress.');
    }

    _isDownloading = true;
    _pauseRequested = false;
    _cancelRequested = false;
    try {
      await _ensureAndroidForegroundNotificationsConfigured();

      final recovered = await _storage.reconcileDescriptor(descriptor);
      if (recovered != null) {
        final record = await registerInstalledModel(recovered);
        onProgress(record.fileSizeBytes, record.fileSizeBytes);
        return ModelDownloadResult(
          status: ModelDownloadResultStatus.completed,
          installedModel: record,
        );
      }

      _activeCancelToken = CancelToken();
      final totalBytes = descriptor.expectedFileSizeBytes;
      onProgress(0, totalBytes);
      final targetFile = await _storage.getInstalledFile(descriptor);
      await targetFile.parent.create(recursive: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      debugPrint(
        'ModelDownloader.download: start download modelId=${descriptor.id} path=${targetFile.path}',
      );
      await _downloadToFile(
        descriptor: descriptor,
        targetFile: targetFile,
        onProgress: onProgress,
      );
      if (!await _storage.isValidInstalledFile(descriptor, file: targetFile)) {
        throw StateError(
          'Downloaded model failed validation: ${targetFile.path}',
        );
      }
      final modelId = await _registerInstalledFile(descriptor, targetFile);
      debugPrint(
        'ModelDownloader.download: install registered modelId=$modelId',
      );

      final record = InstalledModelRecord(
        descriptor: descriptor,
        modelId: modelId,
        path: targetFile.path,
        fileSizeBytes: await targetFile.length(),
        installedAt: DateTime.now(),
      );
      await _storage.saveInstalledModel(record);

      return ModelDownloadResult(
        status: ModelDownloadResultStatus.completed,
        installedModel: record,
      );
    } on SocketException catch (error) {
      if (_pauseRequested) {
        return const ModelDownloadResult(
          status: ModelDownloadResultStatus.paused,
        );
      }
      if (_cancelRequested) {
        return const ModelDownloadResult(
          status: ModelDownloadResultStatus.cancelled,
        );
      }
      throw HttpException(error.message);
    } on HttpException {
      if (_pauseRequested) {
        return const ModelDownloadResult(
          status: ModelDownloadResultStatus.paused,
        );
      }
      if (_cancelRequested) {
        return const ModelDownloadResult(
          status: ModelDownloadResultStatus.cancelled,
        );
      }
      rethrow;
    } finally {
      _activeCancelToken = null;
      _activeTaskId = null;
      _isDownloading = false;
      _pauseRequested = false;
      _cancelRequested = false;
    }
  }

  void pause() {
    if (!_isDownloading) {
      return;
    }
    _pauseRequested = true;
    _activeCancelToken?.cancel();
    final activeTaskId = _activeTaskId;
    if (activeTaskId != null) {
      unawaited(FileDownloader().cancelTaskWithId(activeTaskId));
    }
  }

  void cancel() {
    if (!_isDownloading) {
      return;
    }
    _cancelRequested = true;
    _activeCancelToken?.cancel();
    final activeTaskId = _activeTaskId;
    if (activeTaskId != null) {
      unawaited(FileDownloader().cancelTaskWithId(activeTaskId));
    }
  }

  Future<void> _downloadToFile({
    required ModelDescriptor descriptor,
    required File targetFile,
    required void Function(int downloadedBytes, int totalBytes) onProgress,
  }) async {
    final totalBytes = descriptor.expectedFileSizeBytes;
    final completer = Completer<void>();
    StreamSubscription<TaskUpdate>? subscription;
    final taskId =
        '${descriptor.downloadUrl.hashCode.toUnsigned(32).toRadixString(16)}_${targetFile.path.hashCode.toUnsigned(32).toRadixString(16)}';

    final existingTask = await FileDownloader().taskForId(taskId);
    final DownloadTask task;
    if (existingTask is DownloadTask) {
      task = existingTask;
    } else {
      final (baseDirectory, directory, filename) = await Task.split(
        filePath: targetFile.path,
      );
      task = DownloadTask(
        taskId: taskId,
        url: descriptor.downloadUrl,
        group: _downloadGroup,
        headers: const <String, String>{
          'Connection': 'keep-alive',
          'Cache-Control': 'no-cache, no-store',
          'Pragma': 'no-cache',
        },
        baseDirectory: baseDirectory,
        directory: directory,
        filename: filename,
        requiresWiFi: false,
        allowPause: false,
        priority: 10,
        retries: 3,
        updates: Updates.statusAndProgress,
      );
    }
    _activeTaskId = task.taskId;

    subscription = FileDownloader().updates.listen((update) {
      if (update.task.taskId != task.taskId || completer.isCompleted) {
        return;
      }
      if (update is TaskProgressUpdate) {
        final downloadedBytes = totalBytes <= 0
            ? 0
            : (update.progress.clamp(0, 1) * totalBytes).round();
        onProgress(downloadedBytes, totalBytes);
      } else if (update is TaskStatusUpdate) {
        switch (update.status) {
          case TaskStatus.complete:
            onProgress(totalBytes, totalBytes);
            completer.complete();
            break;
          case TaskStatus.canceled:
            completer.completeError(
              const HttpException('Model download canceled.'),
            );
            break;
          case TaskStatus.failed:
          case TaskStatus.notFound:
            completer.completeError(
              HttpException(
                'Model download failed with status ${update.status.name}.',
              ),
            );
            break;
          default:
            break;
        }
      }
    });

    final queued = existingTask != null || await FileDownloader().enqueue(task);
    if (!queued) {
      await subscription.cancel();
      throw const HttpException('Model download could not be queued.');
    }

    try {
      await completer.future;
    } finally {
      await subscription.cancel();
    }
  }

  static Future<String> _registerInstalledFileWithFlutterGemma(
    ModelDescriptor descriptor,
    File file,
  ) async {
    await FlutterGemma.installModel(
      modelType: descriptor.modelType,
      fileType: descriptor.fileType,
    ).fromFile(file.path).install();
    return descriptor.storageFileName;
  }
}
