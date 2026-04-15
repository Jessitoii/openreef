import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_tool_manifest_adapter.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';

void main() {
  const adapter = McpToolManifestAdapter();

  test('converts primitive MCP tool schema into ToolManifest', () {
    final tool = McpTool.fromJson(
      const <String, Object?>{
        'name': 'calendar_create',
        'description': 'Create a calendar event.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'required': <String>['title', 'allDay'],
          'properties': <String, Object?>{
            'title': <String, Object?>{
              'type': 'string',
              'description': 'Event title.',
            },
            'allDay': <String, Object?>{
              'type': 'boolean',
            },
            'durationMinutes': <String, Object?>{
              'type': 'integer',
              'minimum': 15,
              'maximum': 480,
            },
            'priority': <String, Object?>{
              'type': 'number',
              'enum': <Object?>[0.5, 1.0, 2.0],
            },
          },
        },
      },
    );

    final manifest = adapter.adapt(tool);

    expect(manifest.id, 'calendar_create');
    expect(manifest.category, 'mcp');
    expect(manifest.tags, contains('mcp'));
    expect(manifest.argumentSchema, hasLength(4));

    final titleArgument = manifest.argumentSchema.firstWhere(
      (argument) => argument.name == 'title',
    );
    final priorityArgument = manifest.argumentSchema.firstWhere(
      (argument) => argument.name == 'priority',
    );

    expect(titleArgument.type, ToolArgumentType.string);
    expect(titleArgument.isRequired, isTrue);
    expect(priorityArgument.type, ToolArgumentType.doubleValue);
    expect(priorityArgument.allowedValues, <Object?>[0.5, 1.0, 2.0]);
  });

  test('rejects unsupported nested argument shapes', () {
    final tool = McpTool.fromJson(
      const <String, Object?>{
        'name': 'complex_tool',
        'description': 'Has nested data.',
        'inputSchema': <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{
            'payload': <String, Object?>{
              'type': 'object',
            },
          },
        },
      },
    );

    expect(
      () => adapter.adapt(tool),
      throwsA(isA<McpToolAdaptationException>()),
    );
  });

  test('rejects non-object top level input schemas', () {
    final tool = McpTool.fromJson(
      const <String, Object?>{
        'name': 'raw_string',
        'description': 'Takes a string payload.',
        'inputSchema': <String, Object?>{
          'type': 'string',
        },
      },
    );

    expect(
      () => adapter.adapt(tool),
      throwsA(isA<McpToolAdaptationException>()),
    );
  });
}
