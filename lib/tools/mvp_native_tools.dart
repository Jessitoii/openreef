import 'package:openreef/tools/native_tool_adapters.dart';
import 'package:openreef/tools/tool_manifest.dart';

List<NativeToolHandler> createMvpNativeToolHandlers({
  required DeviceVolumeAdapter volumeAdapter,
  required ClipboardAdapter clipboardAdapter,
  required BatteryAdapter batteryAdapter,
}) {
  return <NativeToolHandler>[
    VolumeSetToolHandler(volumeAdapter),
    ClipboardReadToolHandler(clipboardAdapter),
    BatteryInfoToolHandler(batteryAdapter),
  ];
}

class VolumeSetToolHandler implements NativeToolHandler {
  VolumeSetToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'volume_set',
    description: 'Set the device media volume to a normalized level.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(
        name: 'level',
        type: ToolArgumentType.doubleValue,
        minimum: 0,
        maximum: 1,
      ),
    ],
    tags: <String>['android', 'system', 'audio'],
  );

  final DeviceVolumeAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    NativeToolContext context,
  ) async {
    final level = invocation.arguments['level'] as double;
    final normalizedLevel = level.clamp(0.0, 1.0);
    final appliedLevel = await _adapter.setVolumeLevel(normalizedLevel);
    return NativeToolExecutionResult(
      content: 'Volume set to ${(appliedLevel * 100).round()}%.',
      metadata: <String, Object?>{
        'requestedLevel': normalizedLevel,
        'appliedLevel': appliedLevel,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class ClipboardReadToolHandler implements NativeToolHandler {
  ClipboardReadToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'clipboard_read',
    description: 'Read the current clipboard text content.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
    tags: <String>['android', 'system', 'clipboard'],
  );

  final ClipboardAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    NativeToolContext context,
  ) async {
    final text = await _adapter.readClipboardText();
    final hasContent = text != null && text.isNotEmpty;
    return NativeToolExecutionResult(
      content: hasContent ? text : 'Clipboard is empty.',
      metadata: <String, Object?>{
        'hasContent': hasContent,
        'text': text ?? '',
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}

class BatteryInfoToolHandler implements NativeToolHandler {
  BatteryInfoToolHandler(this._adapter);

  static const ToolManifest _manifest = ToolManifest(
    id: 'battery_info',
    description: 'Read the current device battery status.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
    tags: <String>['android', 'system', 'battery'],
  );

  final BatteryAdapter _adapter;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    NativeToolContext context,
  ) async {
    final snapshot = await _adapter.readBatteryInfo();
    return NativeToolExecutionResult(
      content: 'Battery at ${snapshot.level}% (${snapshot.state.name}).',
      metadata: <String, Object?>{
        'level': snapshot.level,
        'state': snapshot.state.name,
        'isLowPowerMode': snapshot.isLowPowerMode,
        'executedAt': context.now().toIso8601String(),
      },
    );
  }
}
