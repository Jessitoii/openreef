import 'package:flutter/material.dart';
import 'package:openreef/settings/app_settings.dart';
import 'package:openreef/settings/settings_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.settingsController,
    super.key,
  });

  final SettingsController settingsController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, child) {
        final settings = settingsController.settings;
        final theme = Theme.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SETTINGS',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'UI toggles map to the documented settings registry now and can later be surfaced through settings_read/settings_write.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Theme',
              child: SegmentedButton<ReefThemeMode>(
                segments: const <ButtonSegment<ReefThemeMode>>[
                  ButtonSegment<ReefThemeMode>(
                    value: ReefThemeMode.dark,
                    label: Text('Dark'),
                  ),
                  ButtonSegment<ReefThemeMode>(
                    value: ReefThemeMode.light,
                    label: Text('Light'),
                  ),
                  ButtonSegment<ReefThemeMode>(
                    value: ReefThemeMode.system,
                    label: Text('System'),
                  ),
                ],
                selected: <ReefThemeMode>{settings.themeMode},
                onSelectionChanged: (selection) {
                  settingsController.updateThemeMode(selection.first);
                },
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Voice',
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('wake-word-toggle'),
                    value: settings.wakeWordEnabled,
                    title: const Text('Wake Word Enabled'),
                    subtitle: const Text(
                      'Keep the local wake pipeline available for future background integration.',
                    ),
                    contentPadding: EdgeInsets.zero,
                    onChanged: settingsController.updateWakeWordEnabled,
                  ),
                  const Divider(height: 20),
                  DropdownButtonFormField<VoiceTtsEngine>(
                    key: const Key('tts-engine-dropdown'),
                    initialValue: settings.voiceTtsEngine,
                    decoration: const InputDecoration(
                      labelText: 'TTS Engine',
                    ),
                    items: const <DropdownMenuItem<VoiceTtsEngine>>[
                      DropdownMenuItem(
                        value: VoiceTtsEngine.android,
                        child: Text('Android'),
                      ),
                      DropdownMenuItem(
                        value: VoiceTtsEngine.kokoro,
                        child: Text('Kokoro'),
                      ),
                    ],
                    onChanged: (engine) {
                      if (engine != null) {
                        settingsController.updateVoiceTtsEngine(engine);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Wake Sensitivity ${settings.voiceSensitivity.toStringAsFixed(1)}',
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    key: const Key('voice-sensitivity-slider'),
                    min: 0.3,
                    max: 0.9,
                    divisions: 6,
                    value: settings.voiceSensitivity,
                    label: settings.voiceSensitivity.toStringAsFixed(1),
                    onChanged: settingsController.updateVoiceSensitivity,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
