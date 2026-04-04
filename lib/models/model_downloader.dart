import 'dart:async';
import 'dart:io';

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
    HttpClient Function()? clientFactory,
  }) : _storage = storage,
       _clientFactory = clientFactory ?? HttpClient.new;

  final ModelStorage _storage;
  final HttpClient Function() _clientFactory;

  HttpClient? _activeClient;
  bool _pauseRequested = false;
  bool _cancelRequested = false;
  bool _isDownloading = false;

  bool get isDownloading => _isDownloading;

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
    _activeClient = _clientFactory();

    final installedFile = await _storage.getInstalledFile(descriptor);
    final partialFile = await _storage.getPartialFile(descriptor);
    await installedFile.parent.create(recursive: true);

    RandomAccessFile? sink;

    try {
      var existingBytes = await _storage.getPartialBytes(descriptor);

      final request = await _activeClient!.getUrl(
        Uri.parse(descriptor.downloadUrl),
      );
      if (existingBytes > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existingBytes-');
      }

      final response = await request.close();

      if (response.statusCode == HttpStatus.ok && existingBytes > 0) {
        await partialFile.writeAsBytes(const <int>[], flush: true);
        existingBytes = 0;
      }

      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
          await partialFile.exists()) {
        if (await installedFile.exists()) {
          await installedFile.delete();
        }
        final completedFile = await partialFile.rename(installedFile.path);
        final stat = await completedFile.stat();
        return ModelDownloadResult(
          status: ModelDownloadResultStatus.completed,
          installedModel: InstalledModelRecord(
            descriptor: descriptor,
            path: completedFile.path,
            fileSizeBytes: stat.size,
            installedAt: stat.modified,
          ),
        );
      }

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Model download failed with status ${response.statusCode}.',
          uri: Uri.parse(descriptor.downloadUrl),
        );
      }

      sink = await partialFile.open(
        mode:
            existingBytes > 0 &&
                response.statusCode == HttpStatus.partialContent
            ? FileMode.append
            : FileMode.write,
      );

      final totalBytes = _resolveTotalBytes(
        response: response,
        fallbackBytes: descriptor.expectedFileSizeBytes,
        existingBytes: existingBytes,
      );
      var downloadedBytes = existingBytes;
      onProgress(downloadedBytes, totalBytes);

      await for (final chunk in response) {
        if (_cancelRequested) {
          await sink.close();
          if (await partialFile.exists()) {
            await partialFile.delete();
          }
          return const ModelDownloadResult(
            status: ModelDownloadResultStatus.cancelled,
          );
        }

        if (_pauseRequested) {
          await sink.close();
          return const ModelDownloadResult(
            status: ModelDownloadResultStatus.paused,
          );
        }

        sink.writeFromSync(chunk);
        downloadedBytes += chunk.length;
        onProgress(downloadedBytes, totalBytes);
      }

      await sink.close();

      if (_cancelRequested) {
        if (await partialFile.exists()) {
          await partialFile.delete();
        }
        return const ModelDownloadResult(
          status: ModelDownloadResultStatus.cancelled,
        );
      }

      if (_pauseRequested) {
        return const ModelDownloadResult(
          status: ModelDownloadResultStatus.paused,
        );
      }

      if (await installedFile.exists()) {
        await installedFile.delete();
      }
      final completedFile = await partialFile.rename(installedFile.path);
      final stat = await completedFile.stat();
      return ModelDownloadResult(
        status: ModelDownloadResultStatus.completed,
        installedModel: InstalledModelRecord(
          descriptor: descriptor,
          path: completedFile.path,
          fileSizeBytes: stat.size,
          installedAt: stat.modified,
        ),
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
      if (sink != null) {
        try {
          await sink.close();
        } on FileSystemException {
          // The sink may already be closed after a pause or completion branch.
        }
      }
      _activeClient?.close(force: true);
      _activeClient = null;
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
    _activeClient?.close(force: true);
  }

  void cancel() {
    if (!_isDownloading) {
      return;
    }
    _cancelRequested = true;
    _activeClient?.close(force: true);
  }

  int _resolveTotalBytes({
    required HttpClientResponse response,
    required int fallbackBytes,
    required int existingBytes,
  }) {
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
    if (contentRange != null) {
      final slashIndex = contentRange.lastIndexOf('/');
      if (slashIndex >= 0 && slashIndex + 1 < contentRange.length) {
        return int.tryParse(contentRange.substring(slashIndex + 1)) ??
            fallbackBytes;
      }
    }
    if (response.contentLength > 0) {
      if (response.statusCode == HttpStatus.partialContent) {
        return existingBytes + response.contentLength;
      }
      return response.contentLength;
    }
    return fallbackBytes;
  }
}
