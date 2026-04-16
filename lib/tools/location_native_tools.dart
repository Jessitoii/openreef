import 'package:openreef/tools/tool_errors.dart';
import 'package:openreef/tools/tool_execution_context.dart';
import 'package:openreef/tools/tool_manifest.dart';
import 'package:openreef/tools/native_tool_adapters.dart';

class LocationGetToolHandler implements NativeToolHandler {
  LocationGetToolHandler([LocationAdapter? _]);

  static const ToolManifest _manifest = ToolManifest(
    id: 'location_get',
    description: 'Get device current location.',
    category: 'location',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'highAccuracy', type: ToolArgumentType.boolean),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Location fetched.');
  }
}

class GeofenceAddToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'geofence_add',
    description: 'Add a new geofence.',
    category: 'location',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'id', type: ToolArgumentType.string),
      ToolArgumentSpec(name: 'lat', type: ToolArgumentType.doubleValue),
      ToolArgumentSpec(name: 'lon', type: ToolArgumentType.doubleValue),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Geofence added.');
  }
}

class MapsSearchToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'maps_search',
    description: 'Search maps for a query.',
    category: 'location',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'query', type: ToolArgumentType.string),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.success(content: 'Maps opened.');
  }
}

class LocationDistanceToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'location_distance',
    description: 'Calculate distance between coordinates.',
    category: 'location',
    argumentSchema: <ToolArgumentSpec>[
      ToolArgumentSpec(name: 'lat1', type: ToolArgumentType.doubleValue),
      ToolArgumentSpec(name: 'lon1', type: ToolArgumentType.doubleValue),
      ToolArgumentSpec(name: 'lat2', type: ToolArgumentType.doubleValue),
      ToolArgumentSpec(name: 'lon2', type: ToolArgumentType.doubleValue),
    ],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    // Stub calculation
    return NativeToolExecutionResult.success(
      content: 'Distance mocked.',
      metadata: <String, Object?>{'distanceKm': 350.0},
    );
  }
}

class LocationReverseGeocodeToolHandler implements NativeToolHandler {
  static const ToolManifest _manifest = ToolManifest(
    id: 'location_reverse_geocode',
    description: 'Reverse geocode coordinates.',
    category: 'location',
    enabled: false,
    argumentSchema: <ToolArgumentSpec>[],
  );

  @override
  ToolManifest get manifest => _manifest;

  @override
  Future<NativeToolExecutionResult> execute(
    ToolInvocation invocation,
    ToolExecutionContext context,
  ) async {
    return NativeToolExecutionResult.failure(
      error: const ToolExecutionError(
        code: ToolErrorCode.featureUnavailable,
        message: 'feature_unavailable',
      ),
    );
  }
}
