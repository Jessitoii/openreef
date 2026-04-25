import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_descriptor.dart';

enum ModelCardLifecycle {
  discoverable,
  unavailable,
  downloadable,
  downloading,
  downloaded,
  initializing,
  initialized,
  active,
  failedDownload,
  failedInitialization,
  missingToken,
  unsupported,
}

enum ModelDownloadStatus {
  idle,
  preparing,
  downloading,
  paused,
  completed,
  failed,
  cancelling,
  initializing,
}

enum ModelFailureKind { download, initialization }

class ModelCardState {
  const ModelCardState({
    required this.descriptor,
    required this.lifecycle,
    required this.capabilityLabels,
    this.installedRecord,
    this.reason,
  });

  final ModelDescriptor descriptor;
  final ModelCardLifecycle lifecycle;
  final InstalledModelRecord? installedRecord;
  final List<String> capabilityLabels;
  final String? reason;

  bool get isDownloaded => installedRecord != null;
  bool get isInitialized =>
      lifecycle == ModelCardLifecycle.initialized ||
      lifecycle == ModelCardLifecycle.active;
  bool get isActive => lifecycle == ModelCardLifecycle.active;
  bool get showDownloadProgress => lifecycle == ModelCardLifecycle.downloading;

  bool get canRunPrimaryAction {
    return switch (lifecycle) {
      ModelCardLifecycle.discoverable ||
      ModelCardLifecycle.downloadable ||
      ModelCardLifecycle.downloaded ||
      ModelCardLifecycle.initialized ||
      ModelCardLifecycle.failedDownload ||
      ModelCardLifecycle.failedInitialization => true,
      ModelCardLifecycle.downloading ||
      ModelCardLifecycle.initializing ||
      ModelCardLifecycle.active ||
      ModelCardLifecycle.missingToken ||
      ModelCardLifecycle.unsupported ||
      ModelCardLifecycle.unavailable => false,
    };
  }

  String get primaryLabel {
    return switch (lifecycle) {
      ModelCardLifecycle.discoverable ||
      ModelCardLifecycle.downloadable => 'Download',
      ModelCardLifecycle.downloading => 'Downloading...',
      ModelCardLifecycle.downloaded => 'Initialize',
      ModelCardLifecycle.initializing => 'Initializing...',
      ModelCardLifecycle.initialized => 'Set active',
      ModelCardLifecycle.active => 'Active',
      ModelCardLifecycle.failedDownload => 'Retry download',
      ModelCardLifecycle.failedInitialization => 'Retry initialize',
      ModelCardLifecycle.missingToken => 'Add token',
      ModelCardLifecycle.unsupported ||
      ModelCardLifecycle.unavailable => 'Unavailable',
    };
  }

  String get statusLabel {
    return switch (lifecycle) {
      ModelCardLifecycle.discoverable ||
      ModelCardLifecycle.downloadable => 'Available to download',
      ModelCardLifecycle.downloading => 'Downloading',
      ModelCardLifecycle.downloaded => 'Downloaded',
      ModelCardLifecycle.initializing => 'Initializing',
      ModelCardLifecycle.initialized => 'Initialized',
      ModelCardLifecycle.active => 'Active',
      ModelCardLifecycle.failedDownload => 'Download failed',
      ModelCardLifecycle.failedInitialization => 'Initialization failed',
      ModelCardLifecycle.missingToken => 'Token required',
      ModelCardLifecycle.unsupported => 'Unsupported on this device',
      ModelCardLifecycle.unavailable => 'Unavailable',
    };
  }
}

class ModelDownloadState {
  const ModelDownloadState({
    required this.status,
    this.selectedModel,
    this.installedModel,
    this.installedModels = const <InstalledModelRecord>[],
    this.deviceStats,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.errorMessage,
    this.initializedModelId,
    this.failureKind,
    this.failedModelId,
  });

  const ModelDownloadState.idle()
    : status = ModelDownloadStatus.idle,
      selectedModel = null,
      installedModel = null,
      installedModels = const <InstalledModelRecord>[],
      deviceStats = null,
      downloadedBytes = 0,
      totalBytes = 0,
      bytesPerSecond = 0,
      errorMessage = null,
      initializedModelId = null,
      failureKind = null,
      failedModelId = null;

  final ModelDownloadStatus status;
  final ModelDescriptor? selectedModel;
  final InstalledModelRecord? installedModel;
  final List<InstalledModelRecord> installedModels;
  final LiteRtDeviceStats? deviceStats;
  final int downloadedBytes;
  final int totalBytes;
  final double bytesPerSecond;
  final String? errorMessage;
  final String? initializedModelId;
  final ModelFailureKind? failureKind;
  final String? failedModelId;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return downloadedBytes / totalBytes;
  }

  bool get isDownloadInProgress =>
      status == ModelDownloadStatus.preparing ||
      status == ModelDownloadStatus.downloading ||
      status == ModelDownloadStatus.cancelling;

  bool get isInitializing => status == ModelDownloadStatus.initializing;

  bool get isDownloading => isDownloadInProgress || isInitializing;

  Duration? get eta {
    if (bytesPerSecond <= 0 || totalBytes <= downloadedBytes) {
      return null;
    }
    final remainingSeconds = (totalBytes - downloadedBytes) / bytesPerSecond;
    return Duration(seconds: remainingSeconds.ceil());
  }

  bool isCompatible(ModelDescriptor model) {
    final stats = deviceStats;
    if (stats == null) {
      return true;
    }
    return stats.freeRam >= model.minRamGb;
  }

  InstalledModelRecord? installedRecordFor(ModelDescriptor? model) {
    if (model == null) {
      return null;
    }
    for (final record in installedModels) {
      if (record.descriptor.id == model.id) {
        return record;
      }
    }
    if (installedModel?.descriptor.id == model.id) {
      return installedModel;
    }
    return null;
  }

  ModelCardState cardFor(
    ModelDescriptor model, {
    required bool selectedAsActive,
    String? runtimeInitializedModelId,
    bool hasHfToken = false,
  }) {
    final installedRecord = installedRecordFor(model);
    final selected = selectedModel?.id == model.id;
    final initializedId = runtimeInitializedModelId ?? initializedModelId;
    final capabilities = _capabilityLabelsFor(model);

    if (model.task != ReefModelTask.generation) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.unavailable,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason: 'This marketplace installs generation models only.',
      );
    }

    if (selected &&
        failedModelId == model.id &&
        failureKind == ModelFailureKind.download) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.failedDownload,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason: errorMessage,
      );
    }

    if (selected &&
        failedModelId == model.id &&
        failureKind == ModelFailureKind.initialization) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.failedInitialization,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason: errorMessage,
      );
    }

    if (installedRecord == null && model.requiresHfToken && !hasHfToken) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.missingToken,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason: 'This gated Hugging Face model needs a saved access token.',
      );
    }

    if (!isCompatible(model)) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.unsupported,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason:
            'Requires at least ${model.minRamGb.toStringAsFixed(1)} GB free RAM.',
      );
    }

    if (selected && isDownloadInProgress) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.downloading,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
      );
    }

    if (selected && isInitializing) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.initializing,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
      );
    }

    if (installedRecord != null && initializedId == installedRecord.modelId) {
      return ModelCardState(
        descriptor: model,
        lifecycle: selectedAsActive
            ? ModelCardLifecycle.active
            : ModelCardLifecycle.initialized,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
      );
    }

    if (installedRecord != null) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.downloaded,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
      );
    }

    return ModelCardState(
      descriptor: model,
      lifecycle: ModelCardLifecycle.downloadable,
      capabilityLabels: capabilities,
    );
  }

  ModelDownloadState copyWith({
    ModelDownloadStatus? status,
    ModelDescriptor? selectedModel,
    bool clearSelectedModel = false,
    InstalledModelRecord? installedModel,
    bool clearInstalledModel = false,
    List<InstalledModelRecord>? installedModels,
    LiteRtDeviceStats? deviceStats,
    bool clearDeviceStats = false,
    int? downloadedBytes,
    int? totalBytes,
    double? bytesPerSecond,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? initializedModelId,
    bool clearInitializedModelId = false,
    ModelFailureKind? failureKind,
    String? failedModelId,
    bool clearFailure = false,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      selectedModel: clearSelectedModel
          ? null
          : (selectedModel ?? this.selectedModel),
      installedModel: clearInstalledModel
          ? null
          : (installedModel ?? this.installedModel),
      installedModels: installedModels ?? this.installedModels,
      deviceStats: clearDeviceStats ? null : (deviceStats ?? this.deviceStats),
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      initializedModelId: clearInitializedModelId
          ? null
          : (initializedModelId ?? this.initializedModelId),
      failureKind: clearFailure ? null : (failureKind ?? this.failureKind),
      failedModelId: clearFailure
          ? null
          : (failedModelId ?? this.failedModelId),
    );
  }

  static List<String> _capabilityLabelsFor(ModelDescriptor model) {
    final labels = <String>[];
    if (model.task == ReefModelTask.generation) {
      labels.add('Text');
    }
    if (model.task == ReefModelTask.embedding) {
      labels.add('Embeddings');
    }
    if (model.modelType == ModelType.functionGemma) {
      labels.add('Tool calling');
    }
    if (model.multilingual) {
      labels.add('Multilingual');
    }
    if (model.task == ReefModelTask.generation ||
        model.task == ReefModelTask.embedding) {
      labels.add('On device');
    }
    return labels;
  }
}
