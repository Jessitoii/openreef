import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_registry.dart';
import 'package:openreef/models/model_storage.dart';

void main() {
  late Directory tempDirectory;
  late HttpServer server;
  late ModelStorage storage;
  final payload = utf8.encode(List<String>.filled(2048, 'reef').join());

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('openreef-download-');
    storage = ModelStorage(directoryResolver: () async => tempDirectory);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      if (range != null) {
        final match = RegExp(r'bytes=(\d+)-').firstMatch(range);
        start = int.parse(match!.group(1)!);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${payload.length - 1}/${payload.length}',
        );
      }
      final responseBytes = payload.sublist(start);
      request.response.headers.contentLength = responseBytes.length;
      request.response.add(responseBytes);
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('resumes download from an existing partial file', () async {
    final descriptor = const ModelRegistry().findById('gemma-3-1b-it')!;
    final partial = await storage.getPartialFile(descriptor);
    await partial.parent.create(recursive: true);
    await partial.writeAsBytes(payload.sublist(0, 1200), flush: true);

    final downloader = ModelDownloader(storage: storage);
    final resumedDescriptor = _overrideUrl(
      descriptor,
      'http://127.0.0.1:${server.port}/model',
      payload.length,
    );

    final progressEvents = <int>[];
    final result = await downloader.download(
      descriptor: resumedDescriptor,
      onProgress: (downloadedBytes, totalBytes) {
        progressEvents.add(downloadedBytes);
        expect(totalBytes, payload.length);
      },
    );

    expect(result.status, ModelDownloadResultStatus.completed);
    expect(progressEvents.first, 1200);

    final installed = await storage.getInstalledFile(resumedDescriptor);
    expect(await installed.exists(), isTrue);
    expect(await installed.readAsBytes(), payload);
  });
}

final class _OverrideDescriptor extends ModelDescriptor {
  const _OverrideDescriptor({
    required super.id,
    required super.name,
    required super.downloadUrl,
    required super.storageFileName,
    required super.expectedFileSizeBytes,
    required super.contextWindow,
    required super.minRamGb,
    required super.bestFor,
    super.hardwareNotes,
  });
}

ModelDescriptor _overrideUrl(
  ModelDescriptor descriptor,
  String url,
  int expectedBytes,
) {
  return _OverrideDescriptor(
    id: descriptor.id,
    name: descriptor.name,
    downloadUrl: url,
    storageFileName: descriptor.storageFileName,
    expectedFileSizeBytes: expectedBytes,
    contextWindow: descriptor.contextWindow,
    minRamGb: descriptor.minRamGb,
    bestFor: descriptor.bestFor,
    hardwareNotes: descriptor.hardwareNotes,
  );
}
