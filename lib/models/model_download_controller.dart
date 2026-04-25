import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:openreef/models/hugging_face_token_store.dart';
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
    HuggingFaceTokenStore? hfTokenStore,
  }) : _registry = registry,
       _storage = storage,
       _downloader = downloader,
       _bridge = bridge,
       _settingsController = settingsController,
       _hfTokenStore = hfTokenStore,
       _state = const ModelDownloadState.idle();

  final ModelRegistry _registry;
  final ModelStorage _storage;
  final ModelDownloader _downloader;
  final LiteRtBridge _bridge;
  final SettingsController _settingsController;
  final HuggingFaceTokenStore? _hfTokenStore;

  ModelDownloadState _state;
  DateTime? _lastTickAt;
  int _lastTickBytes = 0;
  bool _initialized = false;
  final Map<String, bool> _hfTokenAvailability = <String, bool>{};

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

    await _refreshTokenAvailability();
    final installedModels = await _storage.reconcileInstalledModels(_registry);
    final selectedModel = await _ensureSelectedModel(installedModels);
    final installedModel = _recordFor(installedModels, selectedModel);
    _state = _state.copyWith(
      selectedModel: selectedModel,
      installedModel: installedModel,
      installedModels: installedModels,
      initializedModelId: _projectInitializedModelId(installedModels),
      deviceStats: deviceStats,
      status: installedModel == null
          ? ModelDownloadStatus.idle
          : ModelDownloadStatus.completed,
      downloadedBytes: installedModel?.fileSizeBytes ?? 0,
      totalBytes: installedModel?.fileSizeBytes ?? 0,
      bytesPerSecond: 0,
      clearErrorMessage: true,
      clearFailure: true,
    );
    notifyListeners();
  }

  void selectModel(ModelDescriptor descriptor) {
    final installedModel = _recordFor(_state.installedModels, descriptor);
    _state = _state.copyWith(
      selectedModel: descriptor,
      installedModel: installedModel,
      initializedModelId: _projectInitializedModelId(_state.installedModels),
      status: installedModel == null
          ? ModelDownloadStatus.idle
          : ModelDownloadStatus.completed,
      downloadedBytes: installedModel?.fileSizeBytes ?? 0,
      totalBytes: installedModel?.fileSizeBytes ?? 0,
      bytesPerSecond: 0,
      clearErrorMessage: true,
      clearFailure: true,
    );
    notifyListeners();
  }

  ModelCardState cardStateFor(ModelDescriptor model) {
    return _state.cardFor(
      model,
      selectedAsActive:
          _settingsController.settings.generationModelId == model.id,
      runtimeInitializedModelId: _projectInitializedModelId(
        _state.installedModels,
      ),
      hasHfToken: _hasHfToken(model),
    );
  }

  bool isActive(ModelDescriptor model) => cardStateFor(model).isActive;

  bool isInstalled(ModelDescriptor model) {
    return _state.installedRecordFor(model) != null;
  }

  bool isInitialized(ModelDescriptor model) {
    return cardStateFor(model).isInitialized;
  }

  Future<InstalledModelRecord?> activateSelectedModel() async {
    final descriptor = _state.selectedModel;
    if (descriptor == null) {
      return null;
    }
    final installedModel = await _reconcileSelectedInstall(descriptor);
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

    final initializedModelId = _projectInitializedModelId(installedModels);
    if (initializedModelId != installedModel.modelId) {
      _state = _state.copyWith(
        installedModel: installedModel,
        installedModels: installedModels,
        initializedModelId: initializedModelId,
        status: ModelDownloadStatus.completed,
        downloadedBytes: installedModel.fileSizeBytes,
        totalBytes: installedModel.fileSizeBytes,
        bytesPerSecond: 0,
        errorMessage: 'Initialize this model before making it active.',
      );
      notifyListeners();
      return null;
    }

    _settingsController.updateGenerationModelId(descriptor.id);
    _state = _state.copyWith(
      installedModel: installedModel,
      installedModels: installedModels,
      initializedModelId: initializedModelId,
      status: ModelDownloadStatus.completed,
      downloadedBytes: installedModel.fileSizeBytes,
      totalBytes: installedModel.fileSizeBytes,
      bytesPerSecond: 0,
      clearErrorMessage: true,
      clearFailure: true,
    );
    notifyListeners();
    return installedModel;
  }

  Future<InstalledModelRecord?> startDownload() => downloadSelectedModel();

  Future<InstalledModelRecord?> downloadSelectedModel() async {
    final descriptor = _state.selectedModel;
    if (descriptor == null) {
      return null;
    }

    if (!_state.isCompatible(descriptor)) {
      _state = _state.copyWith(
        errorMessage:
            'This device does not meet the RAM requirement for this model.',
      );
      notifyListeners();
      return null;
    }

    String? authToken;
    if (descriptor.requiresHfToken) {
      authToken = await _readHfTokenFor(descriptor);
      if (authToken == null) {
        await _refreshTokenAvailability();
        _state = _state.copyWith(
          errorMessage:
              'Add a Hugging Face access token before downloading this gated model.',
        );
        notifyListeners();
        return null;
      }
    }

    if (_downloader.isDownloading && !_state.isDownloadInProgress) {
      _downloader.resetStuckDownload();
    }

    final recovered = await _storage.reconcileDescriptor(descriptor);
    if (recovered != null) {
      final installedModel = await _downloader.registerInstalledModel(
        recovered,
      );
      final installedModels = await _storage.listInstalledModels(_registry);
      _state = _state.copyWith(
        status: ModelDownloadStatus.completed,
        installedModel: installedModel,
        installedModels: installedModels,
        initializedModelId: _projectInitializedModelId(installedModels),
        downloadedBytes: installedModel.fileSizeBytes,
        totalBytes: installedModel.fileSizeBytes,
        bytesPerSecond: 0,
        clearErrorMessage: true,
        clearFailure: true,
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
      clearFailure: true,
    );
    notifyListeners();

    try {
      final result = await _downloader.download(
        descriptor: descriptor,
        onProgress: _updateProgress,
        authToken: authToken,
      );

      switch (result.status) {
        case ModelDownloadResultStatus.completed:
          final installedModel = result.installedModel;
          final installedModels = await _storage.listInstalledModels(_registry);
          _state = _state.copyWith(
            status: ModelDownloadStatus.completed,
            installedModel: installedModel,
            installedModels: installedModels,
            initializedModelId: _projectInitializedModelId(installedModels),
            downloadedBytes:
                installedModel?.fileSizeBytes ?? _state.downloadedBytes,
            totalBytes: installedModel?.fileSizeBytes ?? _state.totalBytes,
            bytesPerSecond: 0,
            clearErrorMessage: true,
            clearFailure: true,
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
      final message = error.toString().contains('Task timed out')
          ? 'Model download timed out. Please try again.'
          : error.toString();
      _state = _state.copyWith(
        status: ModelDownloadStatus.failed,
        bytesPerSecond: 0,
        errorMessage: message,
        failureKind: ModelFailureKind.download,
        failedModelId: descriptor.id,
      );
      notifyListeners();
      return null;
    }
  }

  Future<InstalledModelRecord?> initializeSelectedModel() async {
    final descriptor = _state.selectedModel;
    if (descriptor == null) {
      return null;
    }
    final installedModel = await _reconcileSelectedInstall(descriptor);
    final installedModels = await _storage.listInstalledModels(_registry);
    if (installedModel == null) {
      _state = _state.copyWith(
        status: ModelDownloadStatus.idle,
        installedModels: installedModels,
        clearInstalledModel: true,
        errorMessage: 'Download this model before initializing it.',
      );
      notifyListeners();
      return null;
    }

    if (!_state.isCompatible(descriptor)) {
      _state = _state.copyWith(
        installedModel: installedModel,
        installedModels: installedModels,
        errorMessage:
            'This device does not meet the RAM requirement for this model.',
      );
      notifyListeners();
      return null;
    }

    _state = _state.copyWith(
      status: ModelDownloadStatus.initializing,
      installedModel: installedModel,
      installedModels: installedModels,
      downloadedBytes: installedModel.fileSizeBytes,
      totalBytes: installedModel.fileSizeBytes,
      bytesPerSecond: 0,
      clearErrorMessage: true,
      clearFailure: true,
    );
    notifyListeners();

    try {
      await _initializeRuntimeModel(installedModel.modelId);
      final initializedId = _bridge.activeModelId ?? installedModel.modelId;
      _state = _state.copyWith(
        status: ModelDownloadStatus.completed,
        initializedModelId: initializedId,
        downloadedBytes: installedModel.fileSizeBytes,
        totalBytes: installedModel.fileSizeBytes,
        bytesPerSecond: 0,
        clearErrorMessage: true,
        clearFailure: true,
      );
      notifyListeners();
      return installedModel;
    } catch (error) {
      _state = _state.copyWith(
        status: ModelDownloadStatus.failed,
        bytesPerSecond: 0,
        errorMessage: error.toString(),
        failureKind: ModelFailureKind.initialization,
        failedModelId: descriptor.id,
        clearInitializedModelId: true,
      );
      notifyListeners();
      return null;
    }
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
    final selectedModel = await _ensureSelectedModel(installedModels);
    final installedModel = _recordFor(installedModels, selectedModel);
    _state = _state.copyWith(
      selectedModel: selectedModel,
      installedModel: installedModel,
      installedModels: installedModels,
      initializedModelId: _projectInitializedModelId(installedModels),
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
    _state = _state.copyWith(
      status: ModelDownloadStatus.initializing,
      clearErrorMessage: true,
      clearFailure: true,
    );
    notifyListeners();
  }

  void markInitializedModel(String modelId) {
    _state = _state.copyWith(
      status: ModelDownloadStatus.completed,
      initializedModelId: modelId,
      clearErrorMessage: true,
      clearFailure: true,
    );
    notifyListeners();
  }

  void setInitializationError(Object error) {
    _state = _state.copyWith(
      status: ModelDownloadStatus.failed,
      errorMessage: error.toString(),
      failureKind: ModelFailureKind.initialization,
      failedModelId:
          _state.selectedModel?.id ??
          _settingsController.settings.generationModelId,
      clearInitializedModelId: true,
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
      clearInitializedModelId: true,
      selectedModel: installedModel.descriptor,
      downloadedBytes: 0,
      totalBytes: 0,
      bytesPerSecond: 0,
      clearErrorMessage: true,
      clearFailure: true,
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

    if (installedModels.length == 1) {
      return installedModels.single.descriptor;
    }
    return _registry.defaultGenerationModel;
  }

  Future<InstalledModelRecord?> _reconcileSelectedInstall(
    ModelDescriptor descriptor,
  ) async {
    final recovered = await _storage.reconcileDescriptor(descriptor);
    if (recovered == null) {
      return null;
    }
    return _downloader.registerInstalledModel(recovered);
  }

  Future<void> _initializeRuntimeModel(String modelId) async {
    var useNpu = false;
    try {
      final stats = await _bridge.getDeviceStats();
      useNpu = stats?.npuReady ?? false;
    } on PlatformException {
      useNpu = false;
    }

    try {
      await _bridge.initModel(path: modelId, useNpu: useNpu);
    } on PlatformException catch (error) {
      if (error.code != 'ERR_NPU_FALLBACK' || !useNpu) {
        rethrow;
      }
      await _bridge.initModel(path: modelId, useNpu: false);
    }
  }

  String? _projectInitializedModelId(List<InstalledModelRecord> records) {
    final runtimeActiveId = _bridge.activeModelId;
    if (runtimeActiveId != null &&
        records.any((record) => record.modelId == runtimeActiveId)) {
      return runtimeActiveId;
    }
    final projectedId = _state.initializedModelId;
    if (projectedId != null &&
        records.any((record) => record.modelId == projectedId)) {
      return projectedId;
    }
    return null;
  }

  bool _hasHfToken(ModelDescriptor model) {
    if (!model.requiresHfToken) {
      return true;
    }
    return _hfTokenAvailability[model.id] ?? false;
  }

  Future<void> _refreshTokenAvailability() async {
    final tokenStore = _hfTokenStore;
    if (tokenStore == null) {
      return;
    }
    for (final model in _registry.models) {
      if (model.requiresHfToken) {
        _hfTokenAvailability[model.id] = await tokenStore.hasTokenForModel(
          model.id,
        );
      }
    }
  }

  Future<String?> _readHfTokenFor(ModelDescriptor model) async {
    if (!model.requiresHfToken) {
      return null;
    }
    final token = await _hfTokenStore?.readTokenForModel(model.id);
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) {
      _hfTokenAvailability[model.id] = false;
      return null;
    }
    _hfTokenAvailability[model.id] = true;
    return normalized;
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
