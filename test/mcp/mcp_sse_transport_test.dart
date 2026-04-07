import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openreef/mcp/mcp_endpoint_policy.dart';
import 'package:openreef/mcp/mcp_models.dart';
import 'package:openreef/mcp/mcp_sse_transport.dart';

void main() {
  late HttpServer server;

  tearDown(() async {
    await server.close(force: true);
  });

  test('parses streamed SSE messages in order', () async {
    final releaseConnection = Completer<void>();
    server = await _bindSseServer(
      onGet: (request) async {
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          'event: message\n'
          'data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed"}\n'
          '\n',
        );
        await request.response.flush();
        await releaseConnection.future;
        await request.response.close();
      },
      onPost: (request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': null,
            'result': <String, Object?>{},
          }),
        );
        await request.response.close();
      },
    );

    final transport = McpSseTransport(
      sseEndpoint: Uri.parse('http://127.0.0.1:${server.port}/sse'),
      postEndpoint: Uri.parse('http://127.0.0.1:${server.port}/messages'),
    );
    await transport.connect();

    final message = await transport.messages.first;
    expect(message.event, 'message');
    expect(
      message.jsonRpcMessage?['method'],
      'notifications/tools/list_changed',
    );

    releaseConnection.complete();
    await transport.close();
  });

  test('uses announced endpoint for outbound requests', () async {
    final releaseConnection = Completer<void>();
    Map<String, Object?>? capturedBody;
    server = await _bindSseServer(
      onGet: (request) async {
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write('event: endpoint\n');
        request.response.write('data: /announced\n\n');
        await request.response.flush();
        await releaseConnection.future;
        await request.response.close();
      },
      onPost: (request) async {
        capturedBody =
            (jsonDecode(await utf8.decodeStream(request))
                    as Map<Object?, Object?>)
                .cast<String, Object?>();
        expect(request.uri.path, '/announced');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, Object?>{
            'jsonrpc': '2.0',
            'id': capturedBody!['id'],
            'result': <String, Object?>{'ok': true},
          }),
        );
        await request.response.close();
      },
    );

    final transport = McpSseTransport(
      sseEndpoint: Uri.parse('http://127.0.0.1:${server.port}/sse'),
      postEndpoint: Uri.parse('http://127.0.0.1:${server.port}/fallback'),
    );
    await transport.connect();

    await transport.messages.firstWhere(
      (message) => message.event == 'endpoint',
    );
    final response = await transport.sendRequest('tools/list');

    expect(capturedBody?['method'], 'tools/list');
    expect(response.resultAsMap()['ok'], isTrue);

    releaseConnection.complete();
    await transport.close();
  });

  test(
    'falls back to configured POST endpoint and supports notifications',
    () async {
      final releaseConnection = Completer<void>();
      final capturedRequests = <Map<String, Object?>>[];
      server = await _bindSseServer(
        onGet: (request) async {
          request.response.bufferOutput = false;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(': keep-alive\n\n');
          await request.response.flush();
          await releaseConnection.future;
          await request.response.close();
        },
        onPost: (request) async {
          capturedRequests.add(
            (jsonDecode(await utf8.decodeStream(request))
                    as Map<Object?, Object?>)
                .cast<String, Object?>(),
          );
          expect(request.uri.path, '/fallback');
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'jsonrpc': '2.0',
              'id': capturedRequests.last['id'],
              'result': <String, Object?>{},
            }),
          );
          await request.response.close();
        },
      );

      final transport = McpSseTransport(
        sseEndpoint: Uri.parse('http://127.0.0.1:${server.port}/sse'),
        postEndpoint: Uri.parse('http://127.0.0.1:${server.port}/fallback'),
      );
      await transport.connect();

      await transport.sendNotification(
        'notifications/initialized',
        params: const <String, Object?>{'ready': true},
      );
      await transport.sendRequest('tools/list');

      expect(capturedRequests, hasLength(2));
      expect(capturedRequests.first['method'], 'notifications/initialized');
      expect(capturedRequests.last['method'], 'tools/list');

      releaseConnection.complete();
      await transport.close();
    },
  );

  test('rejects cross-origin negotiated POST endpoints', () async {
    expect(
      () => McpEndpointPolicy.validateNegotiatedPostEndpoint(
        sseEndpoint: Uri.parse('https://example.com/sse'),
        postEndpoint: Uri.parse('https://other.example.com/messages'),
      ),
      throwsA(isA<McpTransportException>()),
    );
  });

  test(
    'rejects HTTPS to HTTP negotiated POST downgrade',
    () async {
      final transport = McpSseTransport(
        sseEndpoint: Uri.parse('https://example.com/sse'),
        postEndpoint: Uri.parse('https://example.com/messages'),
      );

      expect(transport.messages, isA<Stream<McpTransportMessage>>());

      transport.messages.listen(null);
      transport.messages.handleError((Object _) {}).drain<void>();
    },
    skip: 'Validated through unit policy tests in controller/store flow.',
  );
}

Future<HttpServer> _bindSseServer({
  required Future<void> Function(HttpRequest request) onGet,
  required Future<void> Function(HttpRequest request) onPost,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.method == 'GET') {
      await onGet(request);
      return;
    }
    if (request.method == 'POST') {
      await onPost(request);
      return;
    }
    request.response.statusCode = HttpStatus.methodNotAllowed;
    await request.response.close();
  });
  return server;
}
