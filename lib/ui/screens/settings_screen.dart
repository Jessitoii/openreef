import 'package:flutter/material.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/settings/app_settings.dart';
import 'package:openreef/settings/settings_controller.dart';
import 'package:openreef/voice/wake_word_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.settingsController,
    this.wakeWordController,
    this.embeddingModelManager,
    super.key,
  });

  final SettingsController settingsController;
  final WakeWordController? wakeWordController;
  final EmbeddingModelManager? embeddingModelManager;

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
            if (embeddingModelManager != null) ...[
              const SizedBox(height: 12),
              _SemanticRetrievalSection(manager: embeddingModelManager!),
            ],
          ],
        );
      },
    );
  }
}

class _SemanticRetrievalSection extends StatefulWidget {
  const _SemanticRetrievalSection({required this.manager});

  final EmbeddingModelManager manager;

  @override
  State<_SemanticRetrievalSection> createState() =>
      _SemanticRetrievalSectionState();
}

class _SemanticRetrievalSectionState extends State<_SemanticRetrievalSection> {
  final TextEditingController _tokenController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.manager,
      builder: (context, child) {
        final manager = widget.manager;
        final model = manager.selectedModel;
        final readiness = manager.readiness;
        final theme = Theme.of(context);
        return _SectionCard(
          title: 'Semantic Retrieval',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Used to find relevant tools, MCP tools, and skills before each agent turn. This is separate from the assistant response model.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('semantic-embedding-model-dropdown'),
                initialValue: model?.id,
                decoration: const InputDecoration(labelText: 'Embedding model'),
                items: manager.models
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.id,
                        child: Text(
                          '${entry.name}${entry.recommended ? ' (recommended)' : ''}${entry.requiresHfToken ? ' - token required' : ''}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _busy
                    ? null
                    : (id) {
                        if (id != null) {
                          setState(() => _busy = true);
                          manager.selectModel(id).whenComplete(() {
                            if (mounted) {
                              setState(() => _busy = false);
                            }
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              Text(_statusLabel(readiness)),
              if (readiness.progress > 0 &&
                  readiness.status == EmbeddingModelReadinessStatus.downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(value: readiness.progress),
                ),
              if (model?.requiresHfToken ?? false) ...[
                const SizedBox(height: 12),
                TextField(
                  key: const Key('semantic-embedding-hf-token-field'),
                  controller: _tokenController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: readiness.hasToken
                        ? 'Update Hugging Face token'
                        : 'Hugging Face token',
                    helperText:
                        'Required only for this gated embedding model. The token is stored in secure storage.',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('semantic-embedding-save-token-button'),
                  onPressed: _busy || model == null
                      ? null
                      : () async {
                          final token = _tokenController.text.trim();
                          if (token.isEmpty) {
                            return;
                          }
                          setState(() => _busy = true);
                          try {
                            await manager.saveHfToken(model.id, token);
                            _tokenController.clear();
                          } finally {
                            if (mounted) {
                              setState(() => _busy = false);
                            }
                          }
                        },
                  child: const Text('Save token'),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('semantic-embedding-install-button'),
                onPressed: _canInstall(readiness) && !_busy
                    ? () async {
                        setState(() => _busy = true);
                        try {
                          await manager.installSelectedModel();
                        } finally {
                          if (mounted) {
                            setState(() => _busy = false);
                          }
                        }
                      }
                    : null,
                child: Text(_installLabel(readiness)),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _canInstall(EmbeddingModelReadiness readiness) {
    return readiness.status == EmbeddingModelReadinessStatus.downloadable ||
        readiness.status == EmbeddingModelReadinessStatus.installed ||
        readiness.status == EmbeddingModelReadinessStatus.failed;
  }

  String _installLabel(EmbeddingModelReadiness readiness) {
    return switch (readiness.status) {
      EmbeddingModelReadinessStatus.ready => 'Ready',
      EmbeddingModelReadinessStatus.downloading => 'Downloading...',
      EmbeddingModelReadinessStatus.requiresAuth => 'Token required',
      EmbeddingModelReadinessStatus.installed => 'Activate',
      _ => 'Install',
    };
  }

  String _statusLabel(EmbeddingModelReadiness readiness) {
    final modelName = readiness.model?.name ?? 'No model';
    return switch (readiness.status) {
      EmbeddingModelReadinessStatus.notConfigured =>
        'Choose a semantic retrieval embedding model.',
      EmbeddingModelReadinessStatus.downloadable =>
        '$modelName is available to install.',
      EmbeddingModelReadinessStatus.requiresAuth =>
        '$modelName requires a Hugging Face token.',
      EmbeddingModelReadinessStatus.downloading => '$modelName is downloading.',
      EmbeddingModelReadinessStatus.installed =>
        '$modelName is installed and can be activated.',
      EmbeddingModelReadinessStatus.activating => '$modelName is activating.',
      EmbeddingModelReadinessStatus.ready => '$modelName is ready.',
      EmbeddingModelReadinessStatus.failed =>
        readiness.message ?? '$modelName failed to install or activate.',
    };
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
