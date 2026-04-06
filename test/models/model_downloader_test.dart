import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_downloader.dart';
import 'package:openreef/models/model_storage.dart';

void main() {
  test('model downloader starts idle', () {
    final downloader = ModelDownloader(storage: ModelStorage());
    expect(downloader.isDownloading, isFalse);
  }, skip: 'FlutterGemma installs require native runtime in unit tests.');
}
