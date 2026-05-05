import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';

class DdgsWebSearchService {
  static const String searchUnavailableMessage =
      'web_search_backend_unavailable';
  static const String fetchUnavailableMessage = 'web_fetch_backend_unavailable';

  Future<String> search(String query) async {
    throw UnsupportedError(searchUnavailableMessage);
  }

  Future<String> fetch(String url) async {
    throw UnsupportedError(fetchUnavailableMessage);
  }
}

class WebSearchToolHandler implements NativeToolHandler {
  WebSearchToolHandler([this._service]);

  static const ToolManifest _manifest = ToolManifest(
    id: 'web_search',
    description: 'Search the web using DuckDuckGo.',
    category: 'research',
    tags: <String>['web'],
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'query', type: ToolArgumentType.string),
    ],
  );

  final DdgsWebSearchService? _service;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final query = (invocation.arguments['query'] as String?)?.trim();
    if (query == null || query.isEmpty) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.invalidArguments,
          message: 'invalid_arguments',
        ),
      );
    }

    if (_service == null) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: 'feature_unavailable',
        ),
      );
    }

    final String results;
    try {
      results = await _service.search(query);
    } on UnsupportedError {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: DdgsWebSearchService.searchUnavailableMessage,
        ),
      );
    }
    if (_isEmptySearchResult(results)) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: DdgsWebSearchService.searchUnavailableMessage,
        ),
      );
    }
    return NativeToolExecutionResult.success(content: results);
  }

  bool _isEmptySearchResult(String results) {
    final normalized = results.replaceAll(RegExp(r'\s+'), '');
    return normalized.isEmpty || normalized == '{"results":[]}';
  }
}

class WebFetchToolHandler implements NativeToolHandler {
  WebFetchToolHandler([this._service]);

  static const ToolManifest _manifest = ToolManifest(
    id: 'web_fetch',
    description: 'Fetch readable text from a URL.',
    category: 'research',
    tags: <String>['web'],
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'url', type: ToolArgumentType.string),
    ],
  );

  final DdgsWebSearchService? _service;

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    final url = (invocation.arguments['url'] as String?)?.trim();
    if (url == null || url.isEmpty) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.invalidArguments,
          message: 'invalid_arguments',
        ),
      );
    }

    if (_service == null) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: 'feature_unavailable',
        ),
      );
    }

    final String text;
    try {
      text = await _service.fetch(url);
    } on UnsupportedError {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: DdgsWebSearchService.fetchUnavailableMessage,
        ),
      );
    }
    if (text.trim().isEmpty) {
      return NativeToolExecutionResult.failure(
        error: const ToolExecutionError(
          code: ToolErrorCode.featureUnavailable,
          message: DdgsWebSearchService.fetchUnavailableMessage,
        ),
      );
    }
    return NativeToolExecutionResult.success(content: text);
  }
}
