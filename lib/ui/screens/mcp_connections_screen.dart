import 'package:flutter/material.dart';
import 'package:openreef/ui/screens/skills_screen.dart';

class McpConnectionsScreen extends StatelessWidget {
  const McpConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreenCard(
      title: 'MCP Connections',
      body:
          'MCP server and connector management will be surfaced here. The route is ready for drawer-based navigation.',
    );
  }
}
