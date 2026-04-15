import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/native_tool_adapters.dart';

class BrightnessSetToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'brightness_set',
    description: 'Set screen brightness.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'level', type: ToolArgumentType.doubleValue),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Brightness set.');
  }
}

class WifiToggleToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'wifi_toggle',
    description: 'Toggle Wi-Fi.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'enabled', type: ToolArgumentType.boolean),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Wi-Fi toggled.');
  }
}

class BluetoothToggleToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'bluetooth_toggle',
    description: 'Toggle Bluetooth.',
    category: 'system',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'enabled', type: ToolArgumentType.boolean),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Bluetooth toggled.');
  }
}

class ScreenLockToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'screen_lock',
    description: 'Lock screen.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Screen locked.');
  }
}

class DeviceInfoToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'device_info',
    description: 'Get device information.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Device info mock.');
  }
}

class AppListToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'app_list',
    description: 'Get list of installed apps.',
    category: 'system',
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'App list mock.');
  }
}
