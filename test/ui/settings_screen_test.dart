import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/ui/screens/settings_screen.dart';

void main() {
  const model = ModelDescriptor(
    id: 'gecko-512',
    name: 'Gecko 512',
    downloadUrl: 'https://example.com/gecko.task',
    modelType: ModelType.general,
    fileType: ModelFileType.binary,
    storageFileName: 'Gecko_512_quant.task',
    expectedFileSizeBytes: 1,
    contextWindow: 0,
    minRamGb: 1,
    bestFor: 'Fixture embedding model.',
    task: ReefModelTask.embedding,
  );

  test('embedding action label does not say install for installed model', () {
    const readiness = EmbeddingModelReadiness(
      status: EmbeddingModelReadinessStatus.installed,
      model: model,
    );

    expect(embeddingReadinessActionLabel(readiness), 'Prepare');
    expect(embeddingReadinessStatusLabel(readiness), contains('Installed'));
    expect(canActOnEmbeddingReadiness(readiness), isTrue);
  });

  test('embedding labels distinguish not installed, preparing, and ready', () {
    const downloadable = EmbeddingModelReadiness(
      status: EmbeddingModelReadinessStatus.downloadable,
      model: model,
    );
    const activating = EmbeddingModelReadiness(
      status: EmbeddingModelReadinessStatus.activating,
      model: model,
    );
    const ready = EmbeddingModelReadiness(
      status: EmbeddingModelReadinessStatus.ready,
      model: model,
    );

    expect(embeddingReadinessActionLabel(downloadable), 'Install');
    expect(embeddingReadinessStatusLabel(downloadable), 'Not installed.');
    expect(embeddingReadinessActionLabel(activating), 'Preparing...');
    expect(embeddingReadinessStatusLabel(activating), 'Preparing...');
    expect(embeddingReadinessActionLabel(ready), 'Ready to use');
    expect(embeddingReadinessStatusLabel(ready), 'Ready to use.');
  });
}
