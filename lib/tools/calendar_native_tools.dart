import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/native_tool_adapters.dart';

class CalendarReadToolHandler implements NativeToolHandler {
  CalendarReadToolHandler([this._dummy]);

  static const ToolManifest _manifest = ToolManifest(
    id: 'calendar_read',
    description: 'Read upcoming calendar events.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'lookbackDays', type: ToolArgumentType.integer),
    ],
  );

  final Object? _dummy;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(
      content: 'No events found.',
      metadata: const <String, Object?>{},
    );
  }
}

class CalendarWriteToolHandler implements NativeToolHandler {
  CalendarWriteToolHandler([this._dummy]);

  static const ToolManifest _manifest = ToolManifest(
    id: 'calendar_write',
    description: 'Create a calendar event.',
    category: 'calendar',
    requiresConfirmation: true,
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'title', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'start', type: ToolArgumentType.string),
    ],
  );

  final Object? _dummy;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(
      content: 'Event created.',
      metadata: const <String, Object?>{},
    );
  }
}
