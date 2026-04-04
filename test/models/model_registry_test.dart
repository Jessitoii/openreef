import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_registry.dart';

void main() {
  test('registry ships curated starter marketplace models', () {
    const registry = ModelRegistry();

    expect(
      registry.models.map((model) => model.id),
      containsAll(<String>[
        'gemma-4-e2b-it',
        'gemma-3n-e2b-it',
        'gemma-3-1b-it',
        'phi-4-mini-it',
      ]),
    );

    final phi = registry.findById('phi-4-mini-it');
    expect(phi, isNotNull);
    expect(phi!.storageFileName, endsWith('.task'));
    expect(phi.downloadUrl, contains('huggingface.co'));
  });
}
