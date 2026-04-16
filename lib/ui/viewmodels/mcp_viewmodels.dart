import 'package:openreef/mcp/mcp_connections_controller.dart';

class ConnectorViewModel {
  const ConnectorViewModel({
    required this.id,
    required this.serviceName,
    required this.category,
    required this.statusLabel,
    required this.toolsStatusLabel,
    required this.isConnected,
    required this.isEnabled,
    required this.isPreset,
  });

  final String id;
  final String serviceName;
  final String category;
  final String statusLabel;       // Human-readable generic status
  final String toolsStatusLabel;  // Translation for "Discovery unknown" etc.
  final bool isConnected;
  final bool isEnabled;
  final bool isPreset;

  factory ConnectorViewModel.fromDomain(McpConnectionState state) {
    String status = 'Stable';
    if (!state.connected) {
      status = 'Offline';
    } else {
      if (!state.enabled) {
        status = 'Active (Disabled)';
      } else {
        status = 'Active';
      }
    }

    String toolsStatus = '';
    if (state.connected) {
      if (state.toolsImportedIntoRuntime) {
        toolsStatus = '${state.tools.length} Tools ready';
      } else if (state.errorMessage != null || state.tools.isEmpty) {
        toolsStatus = 'Tools not fetched yet';
      }
    }

    return ConnectorViewModel(
      id: state.endpointId ?? state.url,
      serviceName: state.serverInfo?.name.isNotEmpty == true ? state.serverInfo!.name : state.url,
      category: 'Integration', // default, update if mapped
      statusLabel: status,
      toolsStatusLabel: toolsStatus,
      isConnected: state.connected,
      isEnabled: state.enabled,
      isPreset: state.endpointId != null, 
    );
  }
}
