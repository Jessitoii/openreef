import 'package:openreef/models/litert_bridge.dart';
import 'package:openreef/models/model_descriptor.dart';

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

class ModelDownloadState {
  const ModelDownloadState({
    required this.status,
    this.selectedModel,
    this.installedModel,
    this.deviceStats,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.bytesPerSecond = 0,
    this.errorMessage,
  });

  const ModelDownloadState.idle()
    : status = ModelDownloadStatus.idle,
      selectedModel = null,
      installedModel = null,
      deviceStats = null,
      downloadedBytes = 0,
      totalBytes = 0,
      bytesPerSecond = 0,
      errorMessage = null;

  final ModelDownloadStatus status;
  final ModelDescriptor? selectedModel;
  final InstalledModelRecord? installedModel;
  final LiteRtDeviceStats? deviceStats;
  final int downloadedBytes;
  final int totalBytes;
  final double bytesPerSecond;
  final String? errorMessage;

  double get progress {
    if (totalBytes <= 0) {
      return 0;
    }
    return downloadedBytes / totalBytes;
  }

  bool get isDownloading =>
      status == ModelDownloadStatus.preparing ||
      status == ModelDownloadStatus.downloading ||
      status == ModelDownloadStatus.initializing;

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

  ModelDownloadState copyWith({
    ModelDownloadStatus? status,
    ModelDescriptor? selectedModel,
    bool clearSelectedModel = false,
    InstalledModelRecord? installedModel,
    bool clearInstalledModel = false,
    LiteRtDeviceStats? deviceStats,
    bool clearDeviceStats = false,
    int? downloadedBytes,
    int? totalBytes,
    double? bytesPerSecond,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ModelDownloadState(
      status: status ?? this.status,
      selectedModel: clearSelectedModel
          ? null
          : (selectedModel ?? this.selectedModel),
      installedModel: clearInstalledModel
          ? null
          : (installedModel ?? this.installedModel),
      deviceStats: clearDeviceStats ? null : (deviceStats ?? this.deviceStats),
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }
}
