import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/mcp/mcp_client.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_transport.dart';

void main() {
  test('initialize stores server capabilities and listTools parses tools', () async {
    final transport = _FakeMcpTransport(
      responses: <String, McpJsonRpcResponse>{
        'initialize': const McpJsonRpcResponse(
          id: 1,
          result: <String, Object?>{
            'protocolVersion': '2024-11-05',
            'serverInfo': <String, Object?>{
              'name': 'github',
              'version': '2.1.0',
            },
            'capabilities': <String, Object?>{
              'tools': <String, Object?>{'listChanged': true},
            },
          },
        ),
        'tools/list': const McpJsonRpcResponse(
          id: 2,
          result: <String, Object?>{
            'tools': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'issues_search',
                'description': 'Search issues.',
                'inputSchema': <String, Object?>{
                  'type': 'object',
                  'required': <String>['query'],
                  'properties': <String, Object?>{
                    'query': <String, Object?>{
                      'type': 'string',
                      'description': 'Search text.',
                    },
                    'limit': <String, Object?>{
                      'type': 'integer',
                      'minimum': 1,
                      'maximum': 20,
                    },
                  },
                },
              },
            ],
          },
        ),
      },
    );
    final client = McpClient(transport);

    final initializeResult = await client.initialize(
      clientInfo: const McpClientInfo(name: 'OpenReef', version: '0.1.0'),
    );
    final tools = await client.listTools();

    expect(initializeResult.serverInfo.name, 'github');
    expect(initializeResult.capabilities['tools'], isA<Map<String, Object?>>());
    expect(transport.notifications, contains('notifications/initialized'));
    expect(tools, hasLength(1));
    expect(tools.single.name, 'issues_search');
    expect(tools.single.inputSchema.required, contains('query'));
    expect(tools.single.inputSchema.properties['limit']?.minimum, 1);
    expect(tools.single.inputSchema.properties['limit']?.maximum, 20);

    await client.close();
  });

  test('listTools rejects use before initialize', () async {
    final client = McpClient(_FakeMcpTransport(responses: const {}));

    expect(
      client.listTools,
      throwsA(isA<McpProtocolException>()),
    );
  });

  test('callTool parses text content after initialize', () async {
    final client = McpClient(
      _FakeMcpTransport(
        responses: <String, McpJsonRpcResponse>{
          'initialize': const McpJsonRpcResponse(
            id: 1,
            result: <String, Object?>{
              'protocolVersion': '2024-11-05',
              'serverInfo': <String, Object?>{
                'name': 'github',
                'version': '2.1.0',
              },
            },
          ),
          'tools/call': const McpJsonRpcResponse(
            id: 2,
            result: <String, Object?>{
              'content': <Map<String, Object?>>[
                <String, Object?>{
                  'type': 'text',
                  'text': 'pong',
                },
              ],
            },
          ),
        },
      ),
    );

    await client.initialize(
      clientInfo: const McpClientInfo(name: 'OpenReef', version: '0.1.0'),
    );
    final result = await client.callTool(name: 'ping');

    expect(result.contentText, 'pong');
  });
}

class _FakeMcpTransport implements McpTransport {
  _FakeMcpTransport({required this.responses});

  final Map<String, McpJsonRpcResponse> responses;
  final List<String> notifications = <String>[];
  bool connected = false;

  @override
  Stream<McpTransportMessage> get messages => const Stream.empty();

  @override
  Future<void> close() async {
    connected = false;
  }

  @override
  Future<void> connect() async {
    connected = true;
  }

  @override
  Future<McpJsonRpcResponse> sendRequest(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    final response = responses[method];
    if (response == null) {
      throw StateError('missing response for $method');
    }
    return response;
  }

  @override
  Future<void> sendNotification(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    notifications.add(method);
  }
}
