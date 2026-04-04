class ModelDescriptor {
  const ModelDescriptor({
    required this.id,
    required this.name,
    required this.downloadUrl,
    required this.storageFileName,
    required this.expectedFileSizeBytes,
    required this.contextWindow,
    required this.minRamGb,
    required this.bestFor,
    this.hardwareNotes,
  });

  final String id;
  final String name;
  final String downloadUrl;
  final String storageFileName;
  final int expectedFileSizeBytes;
  final int contextWindow;
  final double minRamGb;
  final String bestFor;
  final String? hardwareNotes;
}

class InstalledModelRecord {
  const InstalledModelRecord({
    required this.descriptor,
    required this.path,
    required this.fileSizeBytes,
    required this.installedAt,
  });

  final ModelDescriptor descriptor;
  final String path;
  final int fileSizeBytes;
  final DateTime installedAt;
}
