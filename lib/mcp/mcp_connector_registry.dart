import 'package:flutter/material.dart';

enum McpConnectorAuthStrategy { oauth2, pat, apiKey, longLivedToken, manual }

enum McpConnectorSetupType {
  oauth,
  pat,
  apiKey,
  baseUrlToken,
  manualEndpoint,
}

class McpConnectorPreset {
  const McpConnectorPreset({
    required this.id,
    required this.name,
    required this.category,
    required this.authStrategy,
    required this.setupType,
    required this.authLaunchLabel,
    required this.supportsDirectOAuth,
    required this.manualFallbackAllowed,
    required this.icon,
    required this.description,
  });

  final String id;
  final String name;
  final String category;
  final McpConnectorAuthStrategy authStrategy;
  final McpConnectorSetupType setupType;
  final String authLaunchLabel;
  final bool supportsDirectOAuth;
  final bool manualFallbackAllowed;
  final IconData icon;
  final String description;
}

class McpConnectorRegistry {
  static const presets = <McpConnectorPreset>[
    McpConnectorPreset(
      id: 'gmail',
      name: 'Gmail',
      category: 'Email',
      authStrategy: McpConnectorAuthStrategy.oauth2,
      setupType: McpConnectorSetupType.oauth,
      authLaunchLabel: 'Connect Gmail',
      supportsDirectOAuth: true,
      manualFallbackAllowed: false,
      icon: Icons.mail_outline,
      description: 'Search, read, and act on inbox mail.',
    ),
    McpConnectorPreset(
      id: 'calendar',
      name: 'Google Calendar',
      category: 'Scheduling',
      authStrategy: McpConnectorAuthStrategy.oauth2,
      setupType: McpConnectorSetupType.oauth,
      authLaunchLabel: 'Connect Calendar',
      supportsDirectOAuth: true,
      manualFallbackAllowed: false,
      icon: Icons.calendar_month_outlined,
      description: 'Events, attendees, and schedule management.',
    ),
    McpConnectorPreset(
      id: 'drive',
      name: 'Google Drive',
      category: 'Files',
      authStrategy: McpConnectorAuthStrategy.oauth2,
      setupType: McpConnectorSetupType.oauth,
      authLaunchLabel: 'Connect Drive',
      supportsDirectOAuth: true,
      manualFallbackAllowed: false,
      icon: Icons.drive_folder_upload_outlined,
      description: 'Browse, fetch, and organize documents.',
    ),
    McpConnectorPreset(
      id: 'github',
      name: 'GitHub',
      category: 'DevOps',
      authStrategy: McpConnectorAuthStrategy.pat,
      setupType: McpConnectorSetupType.pat,
      authLaunchLabel: 'Connect GitHub',
      supportsDirectOAuth: true,
      manualFallbackAllowed: true,
      icon: Icons.code_outlined,
      description: 'Issues, PRs, repos, and release workflows.',
    ),
    McpConnectorPreset(
      id: 'slack',
      name: 'Slack',
      category: 'Team Chat',
      authStrategy: McpConnectorAuthStrategy.oauth2,
      setupType: McpConnectorSetupType.oauth,
      authLaunchLabel: 'Connect Slack',
      supportsDirectOAuth: true,
      manualFallbackAllowed: false,
      icon: Icons.chat_bubble_outline,
      description: 'Channels, messages, and workspace actions.',
    ),
    McpConnectorPreset(
      id: 'notion',
      name: 'Notion',
      category: 'Knowledge Base',
      authStrategy: McpConnectorAuthStrategy.oauth2,
      setupType: McpConnectorSetupType.oauth,
      authLaunchLabel: 'Connect Notion',
      supportsDirectOAuth: true,
      manualFallbackAllowed: false,
      icon: Icons.article_outlined,
      description: 'Pages, databases, and workspace search.',
    ),
    McpConnectorPreset(
      id: 'home_assistant',
      name: 'Home Assistant',
      category: 'Home Automation',
      authStrategy: McpConnectorAuthStrategy.longLivedToken,
      setupType: McpConnectorSetupType.baseUrlToken,
      authLaunchLabel: 'Connect Home Assistant',
      supportsDirectOAuth: false,
      manualFallbackAllowed: true,
      icon: Icons.home_outlined,
      description: 'Smart home control and device state.',
    ),
    McpConnectorPreset(
      id: 'todoist',
      name: 'Todoist',
      category: 'Tasks',
      authStrategy: McpConnectorAuthStrategy.apiKey,
      setupType: McpConnectorSetupType.apiKey,
      authLaunchLabel: 'Connect Todoist',
      supportsDirectOAuth: false,
      manualFallbackAllowed: true,
      icon: Icons.check_circle_outline,
      description: 'Task capture, edits, and reminders.',
    ),
    McpConnectorPreset(
      id: 'spotify',
      name: 'Spotify',
      category: 'Media',
      authStrategy: McpConnectorAuthStrategy.oauth2,
      setupType: McpConnectorSetupType.oauth,
      authLaunchLabel: 'Connect Spotify',
      supportsDirectOAuth: true,
      manualFallbackAllowed: false,
      icon: Icons.music_note_outlined,
      description: 'Playback, queues, and library access.',
    ),
    McpConnectorPreset(
      id: 'custom_url',
      name: 'Custom URL',
      category: 'Manual',
      authStrategy: McpConnectorAuthStrategy.manual,
      setupType: McpConnectorSetupType.manualEndpoint,
      authLaunchLabel: 'Add custom server',
      supportsDirectOAuth: false,
      manualFallbackAllowed: false,
      icon: Icons.link_outlined,
      description: 'Connect any MCP server by URL.',
    ),
  ];
}

extension McpConnectorAuthStrategyLabel on McpConnectorAuthStrategy {
  String get label => switch (this) {
    McpConnectorAuthStrategy.oauth2 => 'OAuth2',
    McpConnectorAuthStrategy.pat => 'PAT',
    McpConnectorAuthStrategy.apiKey => 'API key',
    McpConnectorAuthStrategy.longLivedToken => 'Long-lived token',
    McpConnectorAuthStrategy.manual => 'Custom URL/manual',
  };
}

extension McpConnectorSetupTypeLabel on McpConnectorSetupType {
  String get label => switch (this) {
    McpConnectorSetupType.oauth => 'OAuth',
    McpConnectorSetupType.pat => 'PAT',
    McpConnectorSetupType.apiKey => 'API key',
    McpConnectorSetupType.baseUrlToken => 'Base URL + token',
    McpConnectorSetupType.manualEndpoint => 'Manual endpoint',
  };
}
