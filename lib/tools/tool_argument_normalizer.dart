import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';

class ToolArgumentNormalizer {
  const ToolArgumentNormalizer();

  ToolCall normalize(
    ToolCall call, {
    required ToolDefinition tool,
    required String? userMessage,
  }) {
    final text = userMessage?.toLowerCase().trim();
    if (text == null || text.isEmpty) {
      return call;
    }

    final nextArgs = Map<String, Object?>.from(call.arguments);
    switch (call.toolId) {
      case 'bluetooth_toggle':
      case 'wifi_toggle':
      case 'flashlight_toggle':
        _setMissingBoolean(nextArgs, 'enabled', _inferEnabled(text));
      case 'volume_set':
      case 'brightness_set':
        _normalizeExistingLevel(nextArgs);
        _setMissingLevel(nextArgs, _inferLevel(text));
      case 'dnd_set':
        _setMissingString(nextArgs, 'mode', _inferDndMode(text));
    }

    if (_sameArguments(call.arguments, nextArgs)) {
      return call;
    }
    return ToolCall(
      id: call.id,
      toolId: call.toolId,
      arguments: Map<String, Object?>.unmodifiable(nextArgs),
      rawArguments: Map<String, Object?>.unmodifiable(nextArgs),
      hasRawArguments: true,
      source: call.source,
    );
  }

  void _setMissingBoolean(Map<String, Object?> args, String key, bool? value) {
    if (args.containsKey(key) || value == null) {
      return;
    }
    args[key] = value;
  }

  void _setMissingString(Map<String, Object?> args, String key, String? value) {
    if (args.containsKey(key) || value == null) {
      return;
    }
    args[key] = value;
  }

  void _setMissingLevel(Map<String, Object?> args, double? level) {
    if (level == null) {
      return;
    }
    if (!args.containsKey('level')) {
      args['level'] = level;
    }
  }

  void _normalizeExistingLevel(Map<String, Object?> args) {
    final rawLevel = args['level'];
    if (rawLevel is num && rawLevel > 1 && rawLevel <= 100) {
      args['level'] = rawLevel / 100;
    }
  }

  bool? _inferEnabled(String text) {
    if (RegExp(r'\b(off|disabled?)\b').hasMatch(text)) {
      return false;
    }
    if (RegExp(r'\b(on|enabled?)\b').hasMatch(text)) {
      return true;
    }
    if (_containsAny(text, const <String>[
      'turn off',
      'switch off',
      'set off',
      'disable',
      'deactivate',
      'shut off',
    ])) {
      return false;
    }
    if (_containsAny(text, const <String>[
      'turn on',
      'switch on',
      'set on',
      'enable',
      'activate',
      'start',
    ])) {
      return true;
    }
    return null;
  }

  double? _inferLevel(String text) {
    if (_containsAny(text, const <String>[
      'all the way up',
      'max',
      'maximum',
      'full volume',
      'full brightness',
      '100%',
      '100 percent',
    ])) {
      return 1;
    }
    if (_containsAny(text, const <String>[
      'mute',
      'silent',
      'all the way down',
      'minimum',
      '0%',
      '0 percent',
    ])) {
      return 0;
    }
    if (_containsAny(text, const <String>['half', '50%', '50 percent'])) {
      return 0.5;
    }

    final percentMatch = RegExp(r'(\d{1,3})\s*(%|percent)').firstMatch(text);
    if (percentMatch == null) {
      return null;
    }
    final percent = int.tryParse(percentMatch.group(1)!);
    if (percent == null) {
      return null;
    }
    return percent.clamp(0, 100) / 100;
  }

  String? _inferDndMode(String text) {
    if (_containsAny(text, const <String>[
      'turn off',
      'switch off',
      'disable',
      'allow all',
    ])) {
      return 'all';
    }
    if (_containsAny(text, const <String>[
      'alarm only',
      'alarms only',
      'only alarms',
    ])) {
      return 'alarms_only';
    }
    if (_containsAny(text, const <String>['priority', 'important only'])) {
      return 'priority_only';
    }
    if (_containsAny(text, const <String>[
      'do not disturb',
      'dnd',
      'turn on',
      'switch on',
      'enable',
    ])) {
      return 'none';
    }
    return null;
  }

  bool _containsAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }

  bool _sameArguments(Map<String, Object?> left, Map<String, Object?> right) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
