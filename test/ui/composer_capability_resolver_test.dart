import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/models/model_capabilities.dart';
import 'package:openreef/ui/chat/attachment_runtime_support.dart';
import 'package:openreef/ui/chat/composer_capability_resolver.dart';
import 'package:openreef/ui/chat/composer_models.dart';

void main() {
  test('text-only model with no runtime support resolves unavailable', () {
    final snapshot = _resolve(
      modelCapabilities: ModelInputCapabilities.textOnly,
      runtimeSupport: const _RuntimeSupport(),
    );

    expect(
      snapshot.availabilityFor(ComposerAttachmentType.image),
      ComposerAttachmentAvailability.unavailable,
    );
    expect(
      snapshot.availabilityFor(ComposerAttachmentType.audio),
      ComposerAttachmentAvailability.unavailable,
    );
    expect(
      snapshot.availabilityFor(ComposerAttachmentType.document),
      ComposerAttachmentAvailability.unavailable,
    );
  });

  test(
    'multimodal model with missing runtime resolves unsupportedByRuntime',
    () {
      final snapshot = _resolve(
        modelCapabilities: const ModelInputCapabilities(
          supportsImageInput: true,
          supportsAudioInput: true,
          supportsDocumentInput: true,
        ),
        runtimeSupport: const _RuntimeSupport(),
      );

      expect(
        snapshot.availabilityFor(ComposerAttachmentType.image),
        ComposerAttachmentAvailability.unsupportedByRuntime,
      );
      expect(
        snapshot.availabilityFor(ComposerAttachmentType.audio),
        ComposerAttachmentAvailability.unsupportedByRuntime,
      );
      expect(
        snapshot.availabilityFor(ComposerAttachmentType.document),
        ComposerAttachmentAvailability.unsupportedByRuntime,
      );
    },
  );

  test(
    'runtime support with model unsupported resolves unsupportedByModel',
    () {
      final snapshot = _resolve(
        modelCapabilities: ModelInputCapabilities.textOnly,
        runtimeSupport: const _RuntimeSupport(
          image: true,
          audio: true,
          document: true,
        ),
      );

      expect(
        snapshot.availabilityFor(ComposerAttachmentType.image),
        ComposerAttachmentAvailability.unsupportedByModel,
      );
      expect(
        snapshot.availabilityFor(ComposerAttachmentType.audio),
        ComposerAttachmentAvailability.unsupportedByModel,
      );
      expect(
        snapshot.availabilityFor(ComposerAttachmentType.document),
        ComposerAttachmentAvailability.unsupportedByModel,
      );
    },
  );

  test('model and runtime support resolves available', () {
    final snapshot = _resolve(
      modelCapabilities: const ModelInputCapabilities(
        supportsImageInput: true,
        supportsAudioInput: true,
        supportsDocumentInput: true,
      ),
      runtimeSupport: const _RuntimeSupport(
        image: true,
        audio: true,
        document: true,
      ),
    );

    expect(
      snapshot.availabilityFor(ComposerAttachmentType.image),
      ComposerAttachmentAvailability.available,
    );
    expect(
      snapshot.availabilityFor(ComposerAttachmentType.audio),
      ComposerAttachmentAvailability.available,
    );
    expect(
      snapshot.availabilityFor(ComposerAttachmentType.document),
      ComposerAttachmentAvailability.available,
    );
  });
}

ComposerCapabilitySnapshot _resolve({
  required ModelInputCapabilities modelCapabilities,
  required AttachmentRuntimeSupport runtimeSupport,
}) {
  return ComposerCapabilityResolver(
    modelCapabilityProvider: StaticActiveModelCapabilityProvider(
      modelCapabilities,
    ),
    runtimeSupport: runtimeSupport,
  ).resolve();
}

class _RuntimeSupport implements AttachmentRuntimeSupport {
  const _RuntimeSupport({
    this.image = false,
    this.audio = false,
    this.document = false,
  });

  final bool image;
  final bool audio;
  final bool document;

  @override
  bool get imagePreprocessingAvailable => image;

  @override
  bool get audioPreprocessingAvailable => audio;

  @override
  bool get documentPreprocessingAvailable => document;
}
