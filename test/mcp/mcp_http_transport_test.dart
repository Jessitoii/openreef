import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/mcp/mcp_http_transport.dart';
import 'package:openreef/mcp/mcp_models.dart';

void main() {
  late HttpServer server;

  tearDown(() async {
    await server.close(force: true);
  });

  test('sends JSON-RPC requests and parses successful responses', () async {
    Map<String, Object?>? capturedBody;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      capturedBody = (jsonDecode(await utf8.decodeStream(request))
              as Map<Object?, Object?>)
          .cast<String, Object?>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': capturedBody!['id'],
          'result': <String, Object?>{
            'serverInfo': <String, Object?>{
              'name': 'calendar',
              'version': '1.0.0',
            },
          },
        }),
      );
      await request.response.close();
    });

    final transport = McpHttpTransport(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/rpc'),
    );

    final response = await transport.sendRequest(
      'initialize',
      params: const <String, Object?>{
        'protocolVersion': '2024-11-05',
      },
    );

    expect(capturedBody?['method'], 'initialize');
    expect(
      (capturedBody?['params'] as Map<Object?, Object?>?)?['protocolVersion'],
      '2024-11-05',
    );
    expect(response.resultAsMap()['serverInfo'], isA<Map<String, Object?>>());

    await transport.close();
  });

  test('surfaces non-200 responses', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });

    final transport = McpHttpTransport(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/rpc'),
    );

    expect(
      () => transport.sendRequest('tools/list'),
      throwsA(isA<McpTransportException>()),
    );

    await transport.close();
  });

  test('surfaces malformed JSON', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{not-json');
      await request.response.close();
    });

    final transport = McpHttpTransport(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/rpc'),
    );

    expect(
      () => transport.sendRequest('tools/list'),
      throwsA(isA<McpProtocolException>()),
    );

    await transport.close();
  });

  test('surfaces JSON-RPC errors', () async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final payload = (jsonDecode(await utf8.decodeStream(request))
              as Map<Object?, Object?>)
          .cast<String, Object?>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': payload['id'],
          'error': <String, Object?>{
            'code': -32601,
            'message': 'method_not_found',
          },
        }),
      );
      await request.response.close();
    });

    final transport = McpHttpTransport(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}/rpc'),
    );

    expect(
      () => transport.sendRequest('tools/list'),
      throwsA(isA<McpProtocolException>()),
    );

    await transport.close();
  });
}
