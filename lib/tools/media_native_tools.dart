import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';

class CameraPhotoToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'camera_photo',
    description: 'Take a photo using the device camera.',
    category: 'media',
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Photo taken.');
  }
}

class CameraScanToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'camera_scan',
    description: 'Scan a QR code or barcode.',
    category: 'media',
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Scanned.');
  }
}

class MediaDisplayToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'media_display',
    description: 'Display an image.',
    category: 'media',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'path', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Image displayed.');
  }
}

class MediaPlayToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'media_play',
    description: 'Play an audio or video file.',
    category: 'media',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'path', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'type', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Media playing.');
  }
}

class ImageAnalyzeToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'image_analyze',
    description: 'Analyze an image with an LLM backend.',
    category: 'media',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'path', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Analysis mock.');
  }
}
