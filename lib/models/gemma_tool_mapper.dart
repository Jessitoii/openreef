import 'package:flutter_gemma/flutter_gemma.dart' as gemma;
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/tools/tool_manifest.dart';

class GemmaToolMapper {
  const GemmaToolMapper();

  List<gemma.Tool> mapAll(List<ToolDefinition> selectedTools) {
    return selectedTools
        .where((tool) => tool.enabled)
        .map(map)
        .toList(growable: false);
  }

  gemma.Tool map(ToolDefinition tool) {
    return gemma.Tool(
      name: tool.id,
      description: _descriptionFor(tool),
      parameters: _parametersFor(tool.argumentSchema),
    );
  }

  String _descriptionFor(ToolDefinition tool) {
    final trimmed = tool.description.trim();
    final suffixes = <String>[
      if (tool.requiresConfirmation) 'Requires confirmation before execution.',
      if (tool.category.trim().isNotEmpty) 'Category: ${tool.category}.',
    ];
    if (suffixes.isEmpty) {
      return trimmed;
    }
    if (trimmed.isEmpty) {
      return suffixes.join(' ');
    }
    return '$trimmed ${suffixes.join(' ')}';
  }

  Map<String, Object?> _parametersFor(List<ToolArgumentSpec> arguments) {
    final properties = <String, Object?>{};
    final required = <String>[];
    for (final argument in arguments) {
      properties[argument.name] = _propertyFor(argument);
      if (argument.isRequired) {
        required.add(argument.name);
      }
    }
    return <String, Object?>{
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };
  }

  Map<String, Object?> _propertyFor(ToolArgumentSpec argument) {
    return <String, Object?>{
      'type': _typeFor(argument.type),
      if (argument.description.trim().isNotEmpty)
        'description': argument.description.trim(),
      if (argument.allowedValues.isNotEmpty) 'enum': argument.allowedValues,
      if (argument.minimum != null) 'minimum': argument.minimum,
      if (argument.maximum != null) 'maximum': argument.maximum,
    };
  }

  String _typeFor(ToolArgumentType type) {
    return switch (type) {
      ToolArgumentType.string => 'string',
      ToolArgumentType.integer => 'integer',
      ToolArgumentType.doubleValue => 'number',
      ToolArgumentType.boolean => 'boolean',
    };
  }
}
