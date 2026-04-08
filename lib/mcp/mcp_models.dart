import 'dart:convert';

class McpException implements Exception {
  const McpException(this.message);

  final String message;

  @override
  String toString() => 'McpException: $message';
}

class McpTransportException extends McpException {
  const McpTransportException(super.message);
}

class McpProtocolException extends McpException {
  const McpProtocolException(super.message);
}

class McpToolAdaptationException extends McpException {
  const McpToolAdaptationException(super.message);
}

class McpClientInfo {
  const McpClientInfo({
    required this.name,
    required this.version,
  });

  final String name;
  final String version;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'version': version,
      };
}

class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.version,
  });

  factory McpServerInfo.fromJson(Map<String, Object?> json) {
    return McpServerInfo(
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
    );
  }

  final String name;
  final String version;
}

class McpInitializeResult {
  const McpInitializeResult({
    required this.protocolVersion,
    required this.serverInfo,
    this.capabilities = const <String, Object?>{},
    this.instructions,
  });

  factory McpInitializeResult.fromJson(Map<String, Object?> json) {
    return McpInitializeResult(
      protocolVersion: json['protocolVersion'] as String? ?? '',
      serverInfo: McpServerInfo.fromJson(
        (json['serverInfo'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
      capabilities: (json['capabilities'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{},
      instructions: json['instructions'] as String?,
    );
  }

  final String protocolVersion;
  final McpServerInfo serverInfo;
  final Map<String, Object?> capabilities;
  final String? instructions;
}

class McpJsonRpcError {
  const McpJsonRpcError({
    required this.code,
    required this.message,
    this.data,
  });

  factory McpJsonRpcError.fromJson(Map<String, Object?> json) {
    return McpJsonRpcError(
      code: (json['code'] as num?)?.toInt() ?? -1,
      message: json['message'] as String? ?? 'unknown_error',
      data: json['data'],
    );
  }

  final int code;
  final String message;
  final Object? data;
}

class McpJsonRpcRequest {
  const McpJsonRpcRequest({
    required this.id,
    required this.method,
    this.params = const <String, Object?>{},
  });

  final int id;
  final String method;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => <String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      };
}

class McpJsonRpcNotification {
  const McpJsonRpcNotification({
    required this.method,
    this.params = const <String, Object?>{},
  });

  final String method;
  final Map<String, Object?> params;

  Map<String, Object?> toJson() => <String, Object?>{
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
      };
}

class McpJsonRpcResponse {
  const McpJsonRpcResponse({
    required this.id,
    this.result,
    this.error,
  });

  factory McpJsonRpcResponse.fromJson(Map<String, Object?> json) {
    return McpJsonRpcResponse(
      id: json['id'],
      result: json['result'],
      error: json['error'] == null
          ? null
          : McpJsonRpcError.fromJson(
              (json['error'] as Map).cast<String, Object?>(),
            ),
    );
  }

  final Object? id;
  final Object? result;
  final McpJsonRpcError? error;

  bool get isError => error != null;

  Map<String, Object?> resultAsMap() {
    final resultMap = result;
    if (resultMap is Map) {
      return resultMap.cast<String, Object?>();
    }
    throw const McpProtocolException('expected_map_result');
  }
}

class McpTransportMessage {
  const McpTransportMessage({
    required this.event,
    required this.data,
    this.jsonRpcMessage,
  });

  factory McpTransportMessage.fromRaw({
    required String event,
    required String data,
  }) {
    final trimmed = data.trim();
    if (trimmed.isEmpty) {
      return McpTransportMessage(event: event, data: data);
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return McpTransportMessage(
          event: event,
          data: data,
          jsonRpcMessage: decoded.cast<String, Object?>(),
        );
      }
    } on FormatException {
      // Keep raw event-only payloads intact.
    }

    return McpTransportMessage(event: event, data: data);
  }

  final String event;
  final String data;
  final Map<String, Object?>? jsonRpcMessage;
}

class McpRuntimeEvent {
  const McpRuntimeEvent({
    required this.sourceId,
    required this.eventName,
    required this.payload,
    required this.receivedAt,
    required this.transportEvent,
  });

  final String sourceId;
  final String eventName;
  final Map<String, Object?> payload;
  final DateTime receivedAt;
  final String transportEvent;
}

enum McpJsonSchemaType {
  object,
  string,
  integer,
  number,
  boolean,
  array,
  unknown,
}

McpJsonSchemaType _parseSchemaType(Object? rawType) {
  if (rawType is String) {
    switch (rawType) {
      case 'object':
        return McpJsonSchemaType.object;
      case 'string':
        return McpJsonSchemaType.string;
      case 'integer':
        return McpJsonSchemaType.integer;
      case 'number':
        return McpJsonSchemaType.number;
      case 'boolean':
        return McpJsonSchemaType.boolean;
      case 'array':
        return McpJsonSchemaType.array;
    }
  }

  if (rawType is List) {
    for (final candidate in rawType) {
      final parsed = _parseSchemaType(candidate);
      if (parsed != McpJsonSchemaType.unknown) {
        return parsed;
      }
    }
  }

  return McpJsonSchemaType.unknown;
}

class McpToolInputSchemaProperty {
  const McpToolInputSchemaProperty({
    required this.name,
    required this.type,
    this.description,
    this.enumValues = const <Object?>[],
    this.minimum,
    this.maximum,
  });

  factory McpToolInputSchemaProperty.fromJson(
    String name,
    Map<String, Object?> json,
  ) {
    final rawEnum = json['enum'];
    final enumValues = rawEnum is List<Object?> ? rawEnum : const <Object?>[];

    return McpToolInputSchemaProperty(
      name: name,
      type: _parseSchemaType(json['type']),
      description: json['description'] as String?,
      enumValues: enumValues,
      minimum: json['minimum'] as num?,
      maximum: json['maximum'] as num?,
    );
  }

  final String name;
  final McpJsonSchemaType type;
  final String? description;
  final List<Object?> enumValues;
  final num? minimum;
  final num? maximum;
}

class McpToolInputSchema {
  const McpToolInputSchema({
    required this.type,
    required this.properties,
    this.required = const <String>{},
  });

  factory McpToolInputSchema.fromJson(Map<String, Object?> json) {
    final rawProperties = json['properties'];
    final properties = <String, McpToolInputSchemaProperty>{};
    if (rawProperties is Map) {
      for (final entry in rawProperties.entries) {
        final value = entry.value;
        if (value is Map) {
          properties[entry.key] = McpToolInputSchemaProperty.fromJson(
            entry.key,
            value.cast<String, Object?>(),
          );
        }
      }
    }

    final rawRequired = json['required'];
    final required = rawRequired is List
        ? rawRequired.whereType<String>().toSet()
        : const <String>{};

    return McpToolInputSchema(
      type: _parseSchemaType(json['type']),
      properties: properties,
      required: required,
    );
  }

  final McpJsonSchemaType type;
  final Map<String, McpToolInputSchemaProperty> properties;
  final Set<String> required;
}

class McpTool {
  const McpTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  factory McpTool.fromJson(Map<String, Object?> json) {
    return McpTool(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      inputSchema: McpToolInputSchema.fromJson(
        (json['inputSchema'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }

  final String name;
  final String description;
  final McpToolInputSchema inputSchema;
}

class McpToolCallResult {
  const McpToolCallResult({
    required this.contentText,
    this.structuredContent = const <String, Object?>{},
    this.rawContent = const <Object?>[],
    this.isError = false,
  });

  factory McpToolCallResult.fromJson(Map<String, Object?> json) {
    final rawContent = json['content'];
    final contentItems = rawContent is List ? List<Object?>.from(rawContent) : const <Object?>[];
    final textBuffer = StringBuffer();

    for (final item in contentItems) {
      if (item is! Map) {
        continue;
      }
      final typedItem = item.cast<String, Object?>();
      if (typedItem['type'] == 'text' && typedItem['text'] is String) {
        if (textBuffer.isNotEmpty) {
          textBuffer.writeln();
        }
        textBuffer.write(typedItem['text'] as String);
      }
    }

    final structuredContent =
        (json['structuredContent'] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{};
    final contentText = textBuffer.toString().trim();

    return McpToolCallResult(
      contentText: contentText.isNotEmpty
          ? contentText
          : jsonEncode(rawContent ?? structuredContent),
      structuredContent: structuredContent,
      rawContent: contentItems,
      isError: json['isError'] as bool? ?? false,
    );
  }

  final String contentText;
  final Map<String, Object?> structuredContent;
  final List<Object?> rawContent;
  final bool isError;
}
