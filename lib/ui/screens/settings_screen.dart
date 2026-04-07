import 'package:flutter/material.dart';
import 'package:openreef/settings/app_settings.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/voice/wake_word_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.settingsController,
    this.wakeWordController,
    super.key,
  });

  final SettingsController settingsController;
  final WakeWordController? wakeWordController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (context, child) {
        final settings = settingsController.settings;
        final theme = Theme.of(context);
        final wakeRuntimeAvailable = wakeWordController?.isAvailable ?? false;
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
                      'Theme settings are active. Voice controls below are experimental until wake-to-agent automation is fully wired.',
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
              title: 'Voice (Experimental)',
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('wake-word-toggle'),
                    value: wakeRuntimeAvailable && settings.wakeWordEnabled,
                    title: const Text('Wake Word Listener (Experimental)'),
                    subtitle: Text(
                      wakeRuntimeAvailable
                          ? 'Starts/stops native wake-word listening only. It does not trigger capture, inference, or spoken responses yet.'
                          : 'Unavailable until a Picovoice access key is provisioned for this build. The wake pipeline remains experimental.',
                    ),
                    contentPadding: EdgeInsets.zero,
                    onChanged: wakeRuntimeAvailable
                        ? settingsController.updateWakeWordEnabled
                        : null,
                  ),
                  const Divider(height: 20),
                  DropdownButtonFormField<VoiceTtsEngine>(
                    key: const Key('tts-engine-dropdown'),
                    initialValue: settings.voiceTtsEngine,
                    decoration: const InputDecoration(
                      labelText: 'TTS Engine (Experimental)',
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
                          wakeRuntimeAvailable
                              ? 'Wake Sensitivity (native listener only) ${settings.voiceSensitivity.toStringAsFixed(1)}'
                              : 'Wake Sensitivity (inactive until wake runtime is configured) ${settings.voiceSensitivity.toStringAsFixed(1)}',
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
                    onChanged: wakeRuntimeAvailable
                        ? settingsController.updateVoiceSensitivity
                        : null,
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
  const _SectionCard({required this.title, required this.child});

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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}
