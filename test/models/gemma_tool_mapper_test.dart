import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/models/gemma_tool_mapper.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';

void main() {
  test('maps schema-bearing tool definitions to Gemma tool declarations', () {
    final mapper = GemmaToolMapper();
    final mapped = mapper.map(
      ToolDefinition(
        id: 'calendar_create',
        embedding: const <double>[1, 0, 0],
        description: 'Create a calendar event.',
        requiresConfirmation: true,
        category: 'calendar',
        argumentSchema: const <ToolArgumentSpec>[
          ToolArgumentSpec(
            name: 'title',
            type: ToolArgumentType.string,
            description: 'Event title',
          ),
          ToolArgumentSpec(
            name: 'duration_minutes',
            type: ToolArgumentType.integer,
            description: 'Duration in minutes',
            isRequired: false,
            minimum: 1,
            maximum: 1440,
          ),
          ToolArgumentSpec(
            name: 'visibility',
            type: ToolArgumentType.string,
            isRequired: false,
            allowedValues: <String>['public', 'private'],
          ),
        ],
        execute: (call) async => const ToolResult.success('ok'),
      ),
    );

    expect(mapped.name, 'calendar_create');
    expect(mapped.description, contains('Create a calendar event.'));
    expect(mapped.description, contains('Requires confirmation'));
    expect(mapped.description, contains('Category: calendar'));
    expect(mapped.parameters['type'], 'object');
    final properties = mapped.parameters['properties']! as Map<String, Object?>;
    expect((properties['title']! as Map<String, Object?>)['type'], 'string');
    expect(
      (properties['duration_minutes']! as Map<String, Object?>)['type'],
      'integer',
    );
    expect(
      (properties['duration_minutes']! as Map<String, Object?>)['minimum'],
      1,
    );
    expect(
      (properties['visibility']! as Map<String, Object?>)['enum'],
      <String>['public', 'private'],
    );
    expect(mapped.parameters['required'], <String>['title']);
  });
}
