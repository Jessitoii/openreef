class CronValidationResult {
  const CronValidationResult._({required this.isValid, this.error});

  const CronValidationResult.valid() : this._(isValid: true);

  const CronValidationResult.invalid(String error)
    : this._(isValid: false, error: error);

  final bool isValid;
  final String? error;
}

class CronExpressionValidator {
  const CronExpressionValidator();

  static const CronExpressionValidator instance = CronExpressionValidator();

  CronValidationResult validate(String expression) {
    final parts = expression
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length != 5) {
      return const CronValidationResult.invalid('invalid_cron_field_count');
    }

    final minute = _validateField(parts[0], minimum: 0, maximum: 59);
    if (minute != null) {
      return minute;
    }

    final hour = _validateField(parts[1], minimum: 0, maximum: 23);
    if (hour != null) {
      return hour;
    }

    if (parts[2] != '*') {
      return const CronValidationResult.invalid(
        'unsupported_cron_day_of_month',
      );
    }
    if (parts[3] != '*') {
      return const CronValidationResult.invalid('unsupported_cron_month');
    }

    final dayOfWeek = _validateField(parts[4], minimum: 0, maximum: 6);
    if (dayOfWeek != null) {
      return dayOfWeek;
    }

    return const CronValidationResult.valid();
  }

  CronValidationResult? _validateField(
    String raw, {
    required int minimum,
    required int maximum,
  }) {
    final segments = raw.split(',');
    if (segments.any((segment) => segment.trim().isEmpty)) {
      return const CronValidationResult.invalid('invalid_cron_segment');
    }

    for (final segment in segments) {
      final normalized = segment.trim();
      if (normalized == '*') {
        continue;
      }
      final stepParts = normalized.split('/');
      if (stepParts.length > 2 || stepParts.first.isEmpty) {
        return const CronValidationResult.invalid('invalid_cron_step');
      }
      if (stepParts.length == 2) {
        final step = int.tryParse(stepParts[1]);
        if (step == null || step <= 0) {
          return const CronValidationResult.invalid('invalid_cron_step');
        }
      }

      final rangePart = stepParts.first;
      if (rangePart == '*') {
        continue;
      }
      final rangeParts = rangePart.split('-');
      if (rangeParts.length == 1) {
        final value = int.tryParse(rangePart);
        if (value == null || value < minimum || value > maximum) {
          return const CronValidationResult.invalid('invalid_cron_value');
        }
        continue;
      }
      if (rangeParts.length != 2) {
        return const CronValidationResult.invalid('invalid_cron_range');
      }
      final start = int.tryParse(rangeParts[0]);
      final end = int.tryParse(rangeParts[1]);
      if (start == null ||
          end == null ||
          start < minimum ||
          end > maximum ||
          start > end) {
        return const CronValidationResult.invalid('invalid_cron_range');
      }
    }

    return null;
  }
}
