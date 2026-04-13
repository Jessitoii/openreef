import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/triggers/trigger_models.dart';

class TriggerPollingPolicy {
  const TriggerPollingPolicy({this.defaultPollMinutes = 15});

  final int defaultPollMinutes;

  int resolvePollMinutes(
    TriggerConfig trigger,
    SettingsController settingsController,
  ) {
    final triggerOverride = trigger.pollIntervalMinutes;
    if (triggerOverride != null) {
      return triggerOverride;
    }

    final globalValue = settingsController.settings.triggerMailPollMinutes;
    if (globalValue > 0) {
      return globalValue;
    }

    return defaultPollMinutes;
  }

  TriggerPollingValidation validateResolvedMinutes(int minutes) {
    if (minutes < 5) {
      return const TriggerPollingValidation.invalid(
        'poll_interval_minimum_5_minutes',
      );
    }
    if (minutes < 15) {
      return const TriggerPollingValidation.invalid(
        'poll_interval_android_unsupported_below_15_minutes',
      );
    }
    return const TriggerPollingValidation.valid();
  }

  bool supportsPolling(TriggerConfig trigger) {
    return trigger.type == TriggerType.interval;
  }
}

class TriggerPollingValidation {
  const TriggerPollingValidation._({
    required this.isValid,
    this.warning,
    this.error,
  });

  const TriggerPollingValidation.valid() : this._(isValid: true);

  const TriggerPollingValidation.warning(String warning)
      : this._(isValid: true, warning: warning);

  const TriggerPollingValidation.invalid(String error)
      : this._(isValid: false, error: error);

  final bool isValid;
  final String? warning;
  final String? error;
}
