import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_storage.dart';

enum ModelDownloadResultStatus { completed, paused, cancelled }

class ModelDownloadResult {
  const ModelDownloadResult({required this.status, this.installedModel});

  final ModelDownloadResultStatus status;
  final InstalledModelRecord? installedModel;
}

class ModelDownloader {
  ModelDownloader({
    required ModelStorage storage,
  }) : _storage = storage;

  static const String _downloadGroup = 'smart_downloads';
  static bool _androidDownloadNotificationsConfigured = false;

  final ModelStorage _storage;
  CancelToken? _activeCancelToken;
  bool _pauseRequested = false;
  bool _cancelRequested = false;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

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
    _activeCancelToken = null;
    _pauseRequested = false;
    _cancelRequested = false;
    _isDownloading = false;
    debugPrint('ModelDownloader.resetStuckDownload: cleared stale download state');
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

      _activeCancelToken = CancelToken();
      final totalBytes = descriptor.expectedFileSizeBytes;
      onProgress(0, totalBytes);

      debugPrint(
        'ModelDownloader.download: start install modelId=${descriptor.id}',
      );
      final installation =
          await FlutterGemma.installModel(
            modelType: descriptor.modelType,
            fileType: descriptor.fileType,
          )
          .fromNetwork(descriptor.downloadUrl, foreground: true)
          .withProgress((progress) {
            final normalized = progress.clamp(0, 100) / 100;
            final downloadedBytes =
                (normalized * totalBytes).round().clamp(0, totalBytes);
            onProgress(downloadedBytes, totalBytes);
          })
          .withCancelToken(_activeCancelToken!)
          .install();
      debugPrint(
        'ModelDownloader.download: install finished modelId=${installation.modelId}',
      );

      final record = InstalledModelRecord(
        descriptor: descriptor,
        modelId: installation.modelId,
        fileSizeBytes: totalBytes,
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
  }

  void cancel() {
    if (!_isDownloading) {
      return;
    }
    _cancelRequested = true;
    _activeCancelToken?.cancel();
  }
}
