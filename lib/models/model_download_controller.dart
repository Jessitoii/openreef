import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_download_state.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';
import 'package:openreef/settings/settings_controller.dart';

class ModelDownloadController extends ChangeNotifier {
  ModelDownloadController({
    required ModelRegistry registry,
    required ModelStorage storage,
    required ModelDownloader downloader,
    required LiteRtBridge bridge,
    required SettingsController settingsController,
  }) : _registry = registry,
       _storage = storage,
       _downloader = downloader,
       _bridge = bridge,
       _settingsController = settingsController,
       _state = const ModelDownloadState.idle();

  final ModelRegistry _registry;
  final ModelStorage _storage;
  final ModelDownloader _downloader;
  final LiteRtBridge _bridge;
  final SettingsController _settingsController;

  ModelDownloadState _state;
  DateTime? _lastTickAt;
  int _lastTickBytes = 0;
  bool _initialized = false;

  ModelDownloadState get state => _state;
  List<ModelDescriptor> get models => _registry.generationModels;

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

    final installedModels = await _storage.reconcileInstalledModels(_registry);
    final selectedModel = await _ensureSelectedModel(installedModels);
    final installedModel = _recordFor(installedModels, selectedModel);
    _state = _state.copyWith(
      selectedModel: selectedModel,
      installedModel: installedModel,
      installedModels: installedModels,
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
    final installedModel = _recordFor(_state.installedModels, descriptor);
    _state = _state.copyWith(
      selectedModel: descriptor,
      installedModel: installedModel,
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

  bool isActive(ModelDescriptor model) {
    return _settingsController.settings.generationModelId == model.id &&
        _state.installedRecordFor(model) != null;
  }

  bool isInstalled(ModelDescriptor model) {
    return _state.installedRecordFor(model) != null;
  }

  Future<InstalledModelRecord?> activateSelectedModel() async {
    final descriptor = _state.selectedModel;
    if (descriptor == null) {
      return null;
    }
    final recovered = await _storage.reconcileDescriptor(descriptor);
    final installedModel = recovered == null
        ? null
        : await _downloader.registerInstalledModel(recovered);
    final installedModels = await _storage.listInstalledModels(_registry);
    if (installedModel == null) {
      _state = _state.copyWith(
        installedModels: installedModels,
        installedModel: null,
        status: ModelDownloadStatus.idle,
        downloadedBytes: 0,
        totalBytes: descriptor.expectedFileSizeBytes,
        bytesPerSecond: 0,
        clearErrorMessage: true,
      );
      notifyListeners();
      return null;
    }
    _settingsController.updateGenerationModelId(descriptor.id);
    _state = _state.copyWith(
      installedModel: installedModel,
      installedModels: installedModels,
      status: ModelDownloadStatus.completed,
      downloadedBytes: installedModel.fileSizeBytes,
      totalBytes: installedModel.fileSizeBytes,
      bytesPerSecond: 0,
      clearErrorMessage: true,
    );
    notifyListeners();
    return installedModel;
  }

  Future<InstalledModelRecord?> startDownload() async {
    final descriptor = _state.selectedModel;
    if (descriptor == null) {
      return null;
    }

    if (_downloader.isDownloading && !_state.isDownloading) {
      _downloader.resetStuckDownload();
    }

    final recovered = await _storage.reconcileDescriptor(descriptor);
    if (recovered != null) {
      final installedModel = await _downloader.registerInstalledModel(
        recovered,
      );
      _settingsController.updateGenerationModelId(descriptor.id);
      final installedModels = await _storage.listInstalledModels(_registry);
      _state = _state.copyWith(
        status: ModelDownloadStatus.completed,
        installedModel: installedModel,
        installedModels: installedModels,
        downloadedBytes: installedModel.fileSizeBytes,
        totalBytes: installedModel.fileSizeBytes,
        bytesPerSecond: 0,
        clearErrorMessage: true,
      );
      notifyListeners();
      return installedModel;
    }

    _lastTickAt = null;
    _lastTickBytes = 0;
    _state = _state.copyWith(
      status: ModelDownloadStatus.preparing,
      clearInstalledModel: true,
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
          final installedModels = await _storage.listInstalledModels(_registry);
          _state = _state.copyWith(
            status: ModelDownloadStatus.completed,
            installedModel: installedModel,
            installedModels: installedModels,
            downloadedBytes:
                installedModel?.fileSizeBytes ?? _state.downloadedBytes,
            totalBytes: installedModel?.fileSizeBytes ?? _state.totalBytes,
            bytesPerSecond: 0,
            clearErrorMessage: true,
          );
          if (installedModel != null) {
            _settingsController.updateGenerationModelId(
              installedModel.descriptor.id,
            );
          }
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
      final message = error.toString().contains('Task timed out')
          ? 'Model download timed out. Please try again.'
          : error.toString();
      _state = _state.copyWith(
        status: ModelDownloadStatus.failed,
        bytesPerSecond: 0,
        errorMessage: message,
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
    final installedModels = await _storage.reconcileInstalledModels(_registry);
    final selectedId = _settingsController.settings.generationModelId;
    final installedModel = selectedId == null
        ? null
        : _recordFor(installedModels, _registry.findById(selectedId));
    _state = _state.copyWith(
      installedModel: installedModel,
      installedModels: installedModels,
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

  Future<void> recoverFromCorruptInstalledModel(
    InstalledModelRecord installedModel,
  ) async {
    await _storage.clearInstalled(installedModel.descriptor);
    await _storage.clearPartial(installedModel.descriptor);

    _state = _state.copyWith(
      status: ModelDownloadStatus.idle,
      clearInstalledModel: true,
      selectedModel: installedModel.descriptor,
      downloadedBytes: 0,
      totalBytes: 0,
      bytesPerSecond: 0,
      clearErrorMessage: true,
    );
    notifyListeners();

    await refreshInstalledModel();
  }

  InstalledModelRecord? _recordFor(
    List<InstalledModelRecord> records,
    ModelDescriptor? descriptor,
  ) {
    if (descriptor == null) {
      return null;
    }
    for (final record in records) {
      if (record.descriptor.id == descriptor.id) {
        return record;
      }
    }
    return null;
  }

  Future<ModelDescriptor?> _ensureSelectedModel(
    List<InstalledModelRecord> installedModels,
  ) async {
    final persistedId = _settingsController.settings.generationModelId;
    final persistedModel = persistedId == null
        ? null
        : _registry.findById(persistedId);
    if (persistedModel != null &&
        persistedModel.task == ReefModelTask.generation) {
      return persistedModel;
    }

    final migratedModel = installedModels.length == 1
        ? installedModels.single.descriptor
        : _registry.defaultGenerationModel;
    if (migratedModel != null) {
      _settingsController.updateGenerationModelId(migratedModel.id);
    }
    return migratedModel;
  }

  void _updateProgress(int downloadedBytes, int totalBytes) {
    if (downloadedBytes < 0 || totalBytes <= 0) {
      return;
    }
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
