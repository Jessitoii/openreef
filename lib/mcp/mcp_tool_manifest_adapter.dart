import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';

class McpToolManifestAdapter {
  const McpToolManifestAdapter();

  ToolManifest adapt(McpTool tool) {
    if (tool.inputSchema.type != McpJsonSchemaType.object) {
      throw McpToolAdaptationException(
        'unsupported_input_schema:${tool.name}:expected_object',
      );
    }

    final arguments = tool.inputSchema.properties.entries
        .map((entry) => _toArgumentSpec(tool, entry.key, entry.value))
        .toList(growable: false);

    return ToolManifest(
      id: tool.name,
      description: tool.description,
      category: 'mcp',
      argumentSchema: arguments,
      requiresConfirmation: false,
      enabled: true,
      tags: const <String>['mcp'],
    );
  }

  ToolArgumentSpec _toArgumentSpec(
    McpTool tool,
    String name,
    McpToolInputSchemaProperty property,
  ) {
    final type = switch (property.type) {
      McpJsonSchemaType.string => ToolArgumentType.string,
      McpJsonSchemaType.integer => ToolArgumentType.integer,
      McpJsonSchemaType.number => ToolArgumentType.doubleValue,
      McpJsonSchemaType.boolean => ToolArgumentType.boolean,
      McpJsonSchemaType.object ||
      McpJsonSchemaType.array ||
      McpJsonSchemaType.unknown => throw McpToolAdaptationException(
          'unsupported_argument_type:${tool.name}:$name:${property.type.name}',
        ),
    };

    return ToolArgumentSpec(
      name: name,
      type: type,
      description: property.description ?? '',
      isRequired: tool.inputSchema.required.contains(name),
      minimum: property.minimum,
      maximum: property.maximum,
      allowedValues: property.enumValues,
    );
  }
}
