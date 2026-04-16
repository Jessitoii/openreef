import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';

class CalendarReadToolHandler implements NativeToolHandler {
  CalendarReadToolHandler([Object? _]);

  static const ToolManifest _manifest = ToolManifest(
    id: 'calendar_read',
    description: 'Read upcoming calendar events.',
    category: 'calendar',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'lookbackDays', type: ToolArgumentType.integer),
    ],
  );

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
  CalendarWriteToolHandler([Object? _]);

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
