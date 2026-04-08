import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/agent/agent_models.dart';
import 'package:openreef/agent/mailbox.dart';
import 'package:openreef/agent/tool_router.dart';
import 'package:openreef/context/context_assembler.dart';
import 'package:openreef/mcp/mcp_client.dart';
import 'package:openreef/mcp/mcp_connection_store.dart';
import 'package:openreef/mcp/mcp_connections_controller.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_runtime_coordinator.dart';
import 'package:openreef/mcp/mcp_secret_store.dart';
import 'package:openreef/mcp/mcp_transport.dart';
import 'package:openreef/memory/memory_index.dart';
import 'package:openreef/memory/memory_storage.dart';
import 'package:openreef/memory/sqlite_memory_storage_backend.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'connected MCP tool is imported into the runtime catalog and surfaced by context assembly',
    () async {
      final runtimeToolCatalog = RuntimeToolCatalog(
        sourceTools: <String, List<ToolDefinition>>{
          'native': <ToolDefinition>[
            ToolDefinition(
              id: 'session_status',
              embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
              description: 'Session status',
              execute: _noopExecute,
            ),
            ToolDefinition(
              id: 'memory_search',
              embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
              description: 'Memory search',
              execute: _noopExecute,
            ),
            ToolDefinition(
              id: 'notify',
              embedding: const <double>[1, 0, 0, 0, 0, 0, 0],
              description: 'Notify the user',
              execute: _noopExecute,
            ),
          ],
        },
      );
      final runtimeCoordinator = McpRuntimeCoordinator(
        toolCatalog: runtimeToolCatalog,
        embedText: (text) async => const <double>[1, 0, 0, 0, 0, 0, 0],
      );
      final storage = await _createMemoryStorage();
      addTearDown(storage.close);
      final memoryIndex = MemoryIndex(storage);
      final controller = McpConnectionsController(
        store: McpConnectionStore(
          storage,
          secretStore: InMemoryMcpSecretStore(),
        ),
        runtimeCoordinator: runtimeCoordinator,
        autoConnectPersisted: false,
        transportFactory: (endpoint) => _SequencedMcpTransport(
          endpoint: endpoint,
          toolLists: <List<Map<String, Object?>>>[
            <Map<String, Object?>>[
              <String, Object?>{
                'name': 'search_docs',
                'description': 'Search external docs.',
                'inputSchema': <String, Object?>{'type': 'object'},
              },
            ],
          ],
        ),
      );

      await controller.connect('https://docs.example.com/sse', persist: false);

      final assembler = ContextAssembler(
        memoryIndex: memoryIndex,
        embedder: const _FixedEmbedder(<double>[1, 0, 0, 0, 0, 0, 0]),
        toolCatalog: runtimeToolCatalog,
        skillCatalog: InMemorySkillCatalog(const <SkillDefinition>[]),
      );
      final selection = await assembler.selectTools(
        userMessage: 'search docs for MCP wiring',
        intentSignal: const IntentSignal(
          primary: 'research',
          secondary: 'general',
          confidence: 0.9,
        ),
      );

      final importedState = controller.connections.value.single;
      expect(importedState.toolsImportedIntoRuntime, isTrue);
      expect(
        runtimeToolCatalog.byId('${importedState.runtimeSourceId}/search_docs'),
        isNotNull,
      );
      expect(
        selection.map((tool) => tool.id),
        contains('${importedState.runtimeSourceId}/search_docs'),
      );
      final assembled = await assembler.assemble(
        sessionKey: 'agent:main',
        userMessage: 'search docs for MCP wiring',
        conversationHistory: const <AgentMessage>[],
        modelContextWindow: 4096,
      );
      expect(assembled.toPrompt(), contains('search_docs'));
      expect(assembled.toPrompt(), contains('Search external docs.'));
    },
  );

  test('routed MCP tool executes through ToolRouter and tools/call', () async {
    final runtimeToolCatalog = RuntimeToolCatalog();
    final runtimeCoordinator = McpRuntimeCoordinator(
      toolCatalog: runtimeToolCatalog,
      embedText: (text) async => const <double>[0, 0, 0, 1, 0, 0, 0],
    );
    final storage = await _createMemoryStorage();
    addTearDown(storage.close);
    final transport = _SequencedMcpTransport(
      endpoint: Uri.parse('https://docs.example.com/sse'),
      toolLists: <List<Map<String, Object?>>>[
        <Map<String, Object?>>[
          <String, Object?>{
            'name': 'ping',
            'description': 'Returns pong',
            'inputSchema': <String, Object?>{'type': 'object'},
          },
        ],
      ],
      toolCallResponses: <String, Map<String, Object?>>{
        'ping': <String, Object?>{
          'content': <Map<String, Object?>>[
            <String, Object?>{'type': 'text', 'text': 'pong'},
          ],
        },
      },
    );
    final controller = McpConnectionsController(
      store: McpConnectionStore(
        storage,
        secretStore: InMemoryMcpSecretStore(),
      ),
      runtimeCoordinator: runtimeCoordinator,
      autoConnectPersisted: false,
      transportFactory: (endpoint) => transport,
    );

    await controller.connect('https://docs.example.com/sse', persist: false);
    final state = controller.connections.value.single;
    final router = ToolRouter(
      catalog: runtimeToolCatalog,
      mailbox: AgentMailbox(),
      confirmToolCall: (call) async => true,
    );

    final result = await router.dispatch(
      ToolCall(
        id: 'call-1',
        toolId: '${state.runtimeSourceId}/ping',
      ),
      sessionKey: 'session-1',
    );

    expect(result.content, 'pong');
    expect(transport.requestedMethods, contains('tools/call'));
  });

  test('refresh atomically replaces the full imported tool set for one source', () async {
    final runtimeToolCatalog = RuntimeToolCatalog();
    final runtimeCoordinator = McpRuntimeCoordinator(
      toolCatalog: runtimeToolCatalog,
      embedText: (text) async => const <double>[0, 0, 0, 1, 0, 0, 0],
    );
    final storage = await _createMemoryStorage();
    addTearDown(storage.close);
    final transport = _SequencedMcpTransport(
      endpoint: Uri.parse('https://docs.example.com/sse'),
      toolLists: <List<Map<String, Object?>>>[
        <Map<String, Object?>>[
          <String, Object?>{
            'name': 'ping',
            'description': 'Returns pong',
            'inputSchema': <String, Object?>{'type': 'object'},
          },
        ],
        <Map<String, Object?>>[
          <String, Object?>{
            'name': 'search_docs',
            'description': 'Search docs',
            'inputSchema': <String, Object?>{'type': 'object'},
          },
        ],
      ],
    );
    final controller = McpConnectionsController(
      store: McpConnectionStore(
        storage,
        secretStore: InMemoryMcpSecretStore(),
      ),
      runtimeCoordinator: runtimeCoordinator,
      autoConnectPersisted: false,
      transportFactory: (endpoint) => transport,
    );

    await controller.connect('https://docs.example.com/sse', persist: false);
    final state = controller.connections.value.single;
    expect(runtimeToolCatalog.byId('${state.runtimeSourceId}/ping'), isNotNull);

    await controller.refresh(state.url);

    expect(runtimeToolCatalog.byId('${state.runtimeSourceId}/ping'), isNull);
    expect(
      runtimeToolCatalog.byId('${state.runtimeSourceId}/search_docs'),
      isNotNull,
    );
    expect(controller.connections.value.single.importedToolCount, 1);
  });

  test('runtime coordinator fails deterministically for stale, missing, untrusted, and secret-missing sessions', () async {
    final runtimeToolCatalog = RuntimeToolCatalog();
    final runtimeCoordinator = McpRuntimeCoordinator(
      toolCatalog: runtimeToolCatalog,
      embedText: (text) async => const <double>[0, 0, 0, 1, 0, 0, 0],
    );
    final transport = _SequencedMcpTransport(
      endpoint: Uri.parse('https://docs.example.com/sse'),
      toolLists: const <List<Map<String, Object?>>>[],
      toolCallResponses: <String, Map<String, Object?>>{
        'ping': <String, Object?>{
          'content': <Map<String, Object?>>[
            <String, Object?>{'type': 'text', 'text': 'pong'},
          ],
        },
      },
    );

    var isActive = true;
    await runtimeCoordinator.replaceSourceTools(
      binding: McpRuntimeSourceBinding(
        sourceId: 'source-a',
        client: transport.client,
        isActive: () => isActive,
        requiresTrust: false,
        trusted: true,
        requiresManualSecretEntry: false,
        hasRequiredSecretMaterial: () async => true,
      ),
      discoveredTools: const <McpTool>[
        McpTool(
          name: 'ping',
          description: 'Returns pong',
          inputSchema: McpToolInputSchema(
            type: McpJsonSchemaType.object,
            properties: <String, McpToolInputSchemaProperty>{},
          ),
        ),
      ],
    );

    isActive = false;
    expect(
      () => runtimeCoordinator.executeTool(
        sourceId: 'source-a',
        runtimeToolId: 'source-a/ping',
        mcpToolName: 'ping',
        arguments: const <String, Object?>{},
      ),
      throwsA(isA<StateError>()),
    );

    runtimeCoordinator.removeSource('source-a');
    expect(
      () => runtimeCoordinator.executeTool(
        sourceId: 'source-a',
        runtimeToolId: 'source-a/ping',
        mcpToolName: 'ping',
        arguments: const <String, Object?>{},
      ),
      throwsA(isA<StateError>()),
    );

    await runtimeCoordinator.replaceSourceTools(
      binding: McpRuntimeSourceBinding(
        sourceId: 'source-b',
        client: transport.client,
        isActive: () => true,
        requiresTrust: true,
        trusted: false,
        requiresManualSecretEntry: false,
        hasRequiredSecretMaterial: () async => true,
      ),
      discoveredTools: const <McpTool>[
        McpTool(
          name: 'ping',
          description: 'Returns pong',
          inputSchema: McpToolInputSchema(
            type: McpJsonSchemaType.object,
            properties: <String, McpToolInputSchemaProperty>{},
          ),
        ),
      ],
    );
    expect(
      () => runtimeCoordinator.executeTool(
        sourceId: 'source-b',
        runtimeToolId: 'source-b/ping',
        mcpToolName: 'ping',
        arguments: const <String, Object?>{},
      ),
      throwsA(isA<StateError>()),
    );

    await runtimeCoordinator.replaceSourceTools(
      binding: McpRuntimeSourceBinding(
        sourceId: 'source-c',
        client: transport.client,
        isActive: () => true,
        requiresTrust: true,
        trusted: true,
        requiresManualSecretEntry: false,
        hasRequiredSecretMaterial: () async => false,
      ),
      discoveredTools: const <McpTool>[
        McpTool(
          name: 'ping',
          description: 'Returns pong',
          inputSchema: McpToolInputSchema(
            type: McpJsonSchemaType.object,
            properties: <String, McpToolInputSchemaProperty>{},
          ),
        ),
      ],
    );
    expect(
      () => runtimeCoordinator.executeTool(
        sourceId: 'source-c',
        runtimeToolId: 'source-c/ping',
        mcpToolName: 'ping',
        arguments: const <String, Object?>{},
      ),
      throwsA(isA<StateError>()),
    );
  });
}

Future<MemoryStorage> _createMemoryStorage() async {
  final storage = MemoryStorage(
    SqliteMemoryStorageBackend(
      path: inMemoryDatabasePath,
      databaseFactory: databaseFactoryFfi,
    ),
  );
  await storage.initialize();
  return storage;
}

Future<ToolResult> _noopExecute(ToolCall call) async {
  return const ToolResult.success('ok');
}

class _FixedEmbedder implements IntentEmbedder {
  const _FixedEmbedder(this._embedding);

  final List<double> _embedding;

  @override
  Future<List<double>> embed(String text) async => _embedding;
}

class _SequencedMcpTransport implements McpTransport {
  _SequencedMcpTransport({
    required this.endpoint,
    required List<List<Map<String, Object?>>> toolLists,
    Map<String, Map<String, Object?>> toolCallResponses = const <String, Map<String, Object?>>{},
  }) : _toolLists = List<List<Map<String, Object?>>>.from(toolLists),
       _toolCallResponses = Map<String, Map<String, Object?>>.from(
         toolCallResponses,
       ) {
    client = McpClient(this);
  }

  final Uri endpoint;
  final List<List<Map<String, Object?>>> _toolLists;
  final Map<String, Map<String, Object?>> _toolCallResponses;
  final List<String> requestedMethods = <String>[];
  final StreamController<McpTransportMessage> _messages =
      StreamController<McpTransportMessage>.broadcast();
  late final McpClient client;

  @override
  Stream<McpTransportMessage> get messages => _messages.stream;

  @override
  Future<void> close() async {
    if (!_messages.isClosed) {
      await _messages.close();
    }
  }

  @override
  Future<void> connect() async {
    _messages.add(
      McpTransportMessage(event: 'endpoint', data: endpoint.toString()),
    );
  }

  @override
  Future<McpJsonRpcResponse> sendRequest(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    requestedMethods.add(method);
    if (method == 'initialize') {
      return const McpJsonRpcResponse(
        id: 1,
        result: <String, Object?>{
          'protocolVersion': '2024-11-05',
          'serverInfo': <String, Object?>{
            'name': 'docs',
            'version': '1.0.0',
          },
        },
      );
    }
    if (method == 'tools/list') {
      final nextTools = _toolLists.isEmpty
          ? const <Map<String, Object?>>[]
          : _toolLists.removeAt(0);
      return McpJsonRpcResponse(
        id: 2,
        result: <String, Object?>{'tools': nextTools},
      );
    }
    if (method == 'tools/call') {
      final toolName = params['name'] as String? ?? '';
      final result = _toolCallResponses[toolName];
      if (result == null) {
        throw StateError('missing_tool_call_response:$toolName');
      }
      return McpJsonRpcResponse(id: 3, result: result);
    }
    throw StateError('unexpected_method:$method');
  }

  @override
  Future<void> sendNotification(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {}
}
