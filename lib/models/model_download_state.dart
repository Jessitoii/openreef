import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_descriptor.dart';

enum ModelCardLifecycle {
  notInstalled,
  authRequired,
  downloading,
  downloaded,
  initializing,
  ready,
  active,
  failed,
  unsupportedDevice,
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
      lifecycle == ModelCardLifecycle.ready ||
      lifecycle == ModelCardLifecycle.active;
  bool get isActive => lifecycle == ModelCardLifecycle.active;
  bool get showDownloadProgress => lifecycle == ModelCardLifecycle.downloading;

  bool get canRunPrimaryAction {
    return switch (lifecycle) {
      ModelCardLifecycle.notInstalled ||
      ModelCardLifecycle.downloaded ||
      ModelCardLifecycle.ready ||
      ModelCardLifecycle.failed ||
      ModelCardLifecycle.authRequired => true,
      ModelCardLifecycle.downloading ||
      ModelCardLifecycle.initializing ||
      ModelCardLifecycle.active ||
      ModelCardLifecycle.unsupportedDevice => false,
    };
  }

  String get primaryLabel {
    return switch (lifecycle) {
      ModelCardLifecycle.notInstalled => 'Download',
      ModelCardLifecycle.authRequired => 'Add HF Token',
      ModelCardLifecycle.downloading => 'Downloading...',
      ModelCardLifecycle.downloaded => 'Initialize',
      ModelCardLifecycle.initializing => 'Initializing...',
      ModelCardLifecycle.ready => 'Activate',
      ModelCardLifecycle.active => 'Active',
      ModelCardLifecycle.failed => 'Retry',
      ModelCardLifecycle.unsupportedDevice => 'Unsupported',
    };
  }

  String get statusLabel {
    return switch (lifecycle) {
      ModelCardLifecycle.notInstalled => 'Not installed',
      ModelCardLifecycle.authRequired => 'Hugging Face token required',
      ModelCardLifecycle.downloading => 'Downloading',
      ModelCardLifecycle.downloaded => 'Downloaded',
      ModelCardLifecycle.initializing => 'Initializing',
      ModelCardLifecycle.ready => 'Ready',
      ModelCardLifecycle.active => 'Active',
      ModelCardLifecycle.failed => 'Failed',
      ModelCardLifecycle.unsupportedDevice => 'Unsupported on this device',
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
        lifecycle: ModelCardLifecycle.unsupportedDevice,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason: 'This marketplace installs generation models only.',
      );
    }

    if (selected && failedModelId == model.id && failureKind != null) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.failed,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason: errorMessage,
      );
    }

    if (installedRecord == null && model.requiresHfToken && !hasHfToken) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.authRequired,
        installedRecord: installedRecord,
        capabilityLabels: capabilities,
        reason: 'This gated Hugging Face model needs a saved access token.',
      );
    }

    if (!isCompatible(model)) {
      return ModelCardState(
        descriptor: model,
        lifecycle: ModelCardLifecycle.unsupportedDevice,
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
            : ModelCardLifecycle.ready,
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
      lifecycle: ModelCardLifecycle.notInstalled,
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
    labels.addAll(model.capabilityMetadata.badges);
    if (model.task == ReefModelTask.embedding) labels.add('Embeddings');
    if (model.multilingual) labels.add('Multilingual');
    labels.add('On device');
    return labels;
  }
}
