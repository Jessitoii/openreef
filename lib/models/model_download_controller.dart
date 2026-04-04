import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_download_state.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';

class ModelDownloadController extends ChangeNotifier {
  ModelDownloadController({
    required ModelRegistry registry,
    required ModelStorage storage,
    required ModelDownloader downloader,
    required LiteRtBridge bridge,
  }) : _registry = registry,
       _storage = storage,
       _downloader = downloader,
       _bridge = bridge,
       _state = const ModelDownloadState.idle();

  final ModelRegistry _registry;
  final ModelStorage _storage;
  final ModelDownloader _downloader;
  final LiteRtBridge _bridge;

  ModelDownloadState _state;
  DateTime? _lastTickAt;
  int _lastTickBytes = 0;
  bool _initialized = false;

  ModelDownloadState get state => _state;
  List<ModelDescriptor> get models => _registry.models;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    LiteRtDeviceStats? deviceStats;
    try {
      deviceStats = await _bridge.getDeviceStats();
    } on PlatformException {
      deviceStats = null;
    }

    final installedModel = await _storage.getActiveInstalledModel(_registry);
    final defaultSelection =
        installedModel?.descriptor ?? _pickRecommendedModel(deviceStats);
    _state = _state.copyWith(
      selectedModel: defaultSelection,
      installedModel: installedModel,
      deviceStats: deviceStats,
      status: installedModel == null
          ? ModelDownloadStatus.idle
          : ModelDownloadStatus.completed,
      downloadedBytes: installedModel?.fileSizeBytes ?? 0,
      totalBytes: installedModel?.fileSizeBytes ?? 0,
      bytesPerSecond: 0,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  void selectModel(ModelDescriptor descriptor) {
    _state = _state.copyWith(
      selectedModel: descriptor,
      clearErrorMessage: true,
    );
    notifyListeners();
  }

  Future<InstalledModelRecord?> startDownload() async {
    final descriptor = _state.selectedModel;
    if (descriptor == null) {
      return null;
    }

    _lastTickAt = null;
    _lastTickBytes = 0;
    _state = _state.copyWith(
      status: ModelDownloadStatus.preparing,
      installedModel: null,
      downloadedBytes: await _storage.getPartialBytes(descriptor),
      totalBytes: descriptor.expectedFileSizeBytes,
      bytesPerSecond: 0,
      clearErrorMessage: true,
    );
    notifyListeners();

    try {
      final result = await _downloader.download(
        descriptor: descriptor,
        onProgress: _updateProgress,
      );

      switch (result.status) {
        case ModelDownloadResultStatus.completed:
          final installedModel = result.installedModel;
          _state = _state.copyWith(
            status: ModelDownloadStatus.completed,
            installedModel: installedModel,
            downloadedBytes:
                installedModel?.fileSizeBytes ?? _state.downloadedBytes,
            totalBytes: installedModel?.fileSizeBytes ?? _state.totalBytes,
            bytesPerSecond: 0,
            clearErrorMessage: true,
          );
          notifyListeners();
          return installedModel;
        case ModelDownloadResultStatus.paused:
          _state = _state.copyWith(
            status: ModelDownloadStatus.paused,
            bytesPerSecond: 0,
          );
          notifyListeners();
          return null;
        case ModelDownloadResultStatus.cancelled:
          _state = _state.copyWith(
            status: ModelDownloadStatus.idle,
            downloadedBytes: 0,
            totalBytes: descriptor.expectedFileSizeBytes,
            bytesPerSecond: 0,
            clearErrorMessage: true,
          );
          notifyListeners();
          return null;
      }
    } catch (error) {
      _state = _state.copyWith(
        status: ModelDownloadStatus.failed,
        bytesPerSecond: 0,
        errorMessage: error.toString(),
      );
      notifyListeners();
      return null;
    }
  }

  void pauseDownload() {
    _downloader.pause();
  }

  Future<void> cancelDownload() async {
    final descriptor = _state.selectedModel;
    _state = _state.copyWith(status: ModelDownloadStatus.cancelling);
    notifyListeners();
    _downloader.cancel();
    if (descriptor != null) {
      await _storage.clearPartial(descriptor);
      _state = _state.copyWith(
        status: ModelDownloadStatus.idle,
        downloadedBytes: 0,
        totalBytes: descriptor.expectedFileSizeBytes,
        bytesPerSecond: 0,
        clearErrorMessage: true,
      );
      notifyListeners();
    }
  }

  Future<InstalledModelRecord?> refreshInstalledModel() async {
    final installedModel = await _storage.getActiveInstalledModel(_registry);
    _state = _state.copyWith(
      installedModel: installedModel,
      status: installedModel == null
          ? ModelDownloadStatus.idle
          : ModelDownloadStatus.completed,
      downloadedBytes: installedModel?.fileSizeBytes ?? 0,
      totalBytes: installedModel?.fileSizeBytes ?? 0,
    );
    notifyListeners();
    return installedModel;
  }

  void markInitializingModel() {
    _state = _state.copyWith(status: ModelDownloadStatus.initializing);
    notifyListeners();
  }

  void setInitializationError(Object error) {
    _state = _state.copyWith(
      status: ModelDownloadStatus.failed,
      errorMessage: error.toString(),
    );
    notifyListeners();
  }

  ModelDescriptor _pickRecommendedModel(LiteRtDeviceStats? stats) {
    if (stats == null) {
      return _registry.models.first;
    }
    for (final descriptor in _registry.models) {
      if (stats.freeRam >= descriptor.minRamGb) {
        return descriptor;
      }
    }
    return _registry.models.last;
  }

  void _updateProgress(int downloadedBytes, int totalBytes) {
    final now = DateTime.now();
    var bytesPerSecond = _state.bytesPerSecond;
    if (_lastTickAt != null) {
      final elapsedMs = now.difference(_lastTickAt!).inMilliseconds;
      if (elapsedMs > 0) {
        final deltaBytes = downloadedBytes - _lastTickBytes;
        bytesPerSecond = (deltaBytes * 1000) / elapsedMs;
      }
    }
    _lastTickAt = now;
    _lastTickBytes = downloadedBytes;

    _state = _state.copyWith(
      status: ModelDownloadStatus.downloading,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      bytesPerSecond: bytesPerSecond,
      clearErrorMessage: true,
    );
    notifyListeners();
  }
}
