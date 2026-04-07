import 'dart:typed_data';

class MemoryEmbeddingRecord {
  const MemoryEmbeddingRecord({
    required this.memoryKey,
    required this.modelId,
    required this.embedding,
    required this.normalizedContent,
    required this.updatedAt,
  });

  final String memoryKey;
  final String modelId;
  final List<double> embedding;
  final String normalizedContent;
  final DateTime updatedAt;

  Uint8List toBlob() {
    final bytes = ByteData(embedding.length * 4);
    for (var index = 0; index < embedding.length; index++) {
      bytes.setFloat32(index * 4, embedding[index], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  static List<double> fromBlob(Uint8List blob) {
    final data = ByteData.sublistView(blob);
    final values = <double>[];
    for (var index = 0; index < blob.lengthInBytes; index += 4) {
      values.add(data.getFloat32(index, Endian.little));
    }
    return List<double>.unmodifiable(values);
  }
}
