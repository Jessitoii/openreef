import 'package:openreef/models/model_capabilities.dart';
import 'package:openreef/ui/chat/attachment_runtime_support.dart';
import 'package:openreef/ui/chat/composer_models.dart';

abstract class ActiveModelCapabilityProvider {
  ModelInputCapabilities get currentCapabilities;
}

class StaticActiveModelCapabilityProvider
    implements ActiveModelCapabilityProvider {
  const StaticActiveModelCapabilityProvider(this.currentCapabilities);

  @override
  final ModelInputCapabilities currentCapabilities;
}

class CallbackActiveModelCapabilityProvider
    implements ActiveModelCapabilityProvider {
  const CallbackActiveModelCapabilityProvider(this.readCapabilities);

  final ModelInputCapabilities Function() readCapabilities;

  @override
  ModelInputCapabilities get currentCapabilities => readCapabilities();
}

class ComposerCapabilitySnapshot {
  const ComposerCapabilitySnapshot(this.availability);

  final Map<ComposerAttachmentType, ComposerAttachmentAvailability>
  availability;

  ComposerAttachmentAvailability availabilityFor(ComposerAttachmentType type) {
    return availability[type] ?? ComposerAttachmentAvailability.unavailable;
  }
}

class ComposerCapabilityResolver {
  const ComposerCapabilityResolver({
    required this.modelCapabilityProvider,
    required this.runtimeSupport,
  });

  final ActiveModelCapabilityProvider modelCapabilityProvider;
  final AttachmentRuntimeSupport runtimeSupport;

  ComposerCapabilitySnapshot resolve() {
    final modelCaps = modelCapabilityProvider.currentCapabilities;
    return ComposerCapabilitySnapshot(
      <ComposerAttachmentType, ComposerAttachmentAvailability>{
        ComposerAttachmentType.image: _resolveType(
          modelSupports: modelCaps.supportsImageInput,
          runtimeSupports: runtimeSupport.imagePreprocessingAvailable,
        ),
        ComposerAttachmentType.audio: _resolveType(
          modelSupports: modelCaps.supportsAudioInput,
          runtimeSupports: runtimeSupport.audioPreprocessingAvailable,
        ),
        ComposerAttachmentType.document: _resolveType(
          modelSupports: modelCaps.supportsDocumentInput,
          runtimeSupports: runtimeSupport.documentPreprocessingAvailable,
        ),
      },
    );
  }

  ComposerAttachmentAvailability _resolveType({
    required bool modelSupports,
    required bool runtimeSupports,
  }) {
    if (!modelSupports && !runtimeSupports) {
      return ComposerAttachmentAvailability.unavailable;
    }
    if (!modelSupports) {
      return ComposerAttachmentAvailability.unsupportedByModel;
    }
    if (!runtimeSupports) {
      return ComposerAttachmentAvailability.unsupportedByRuntime;
    }
    return ComposerAttachmentAvailability.available;
  }
}
