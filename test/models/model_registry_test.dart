import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_registry.dart';

void main() {
  test('registry ships curated starter marketplace models', () {
    const registry = ModelRegistry();

    expect(
      registry.models.map((model) => model.id),
      containsAll(<String>[
        'gemma-4-e2b-it',
        'function-gemma-270m-it',
        'gecko-256',
        'gecko-512',
      ]),
    );

    final gemma = registry.findById('gemma-4-e2b-it');
    expect(gemma, isNotNull);
    expect(gemma!.storageFileName, 'gemma-4-E2B-it.litertlm');
    expect(gemma.downloadUrl, contains('huggingface.co'));

    final functionGemma = registry.findById('function-gemma-270m-it');
    expect(functionGemma, isNotNull);
    expect(
      functionGemma!.storageFileName,
      'mobile-actions_q8_ekv1024.litertlm',
    );
  });
}
