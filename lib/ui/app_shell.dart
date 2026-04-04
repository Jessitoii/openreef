import 'package:flutter/material.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/ui/mock_chat_session.dart';
import 'package:openreef/ui/screens/chat_screen.dart';
import 'package:openreef/ui/screens/settings_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    required this.settingsController,
    required this.chatSession,
    super.key,
  });

  final SettingsController settingsController;
  final MockChatSession chatSession;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      ChatScreen(chatSession: widget.chatSession),
      SettingsScreen(settingsController: widget.settingsController),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: screens,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.terminal),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }
}
