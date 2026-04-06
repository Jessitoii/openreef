import 'package:flutter/material.dart';
import 'package:openreef/models/model_descriptor.dart';
import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/models/model_download_state.dart';
import 'package:openreef/ui/app_theme.dart';

class ModelDownloadScreen extends StatefulWidget {
  const ModelDownloadScreen({
    required this.controller,
    required this.onModelReady,
    super.key,
  });

  final ModelDownloadController controller;
  final Future<void> Function() onModelReady;

  @override
  State<ModelDownloadScreen> createState() => _ModelDownloadScreenState();
}

class _ModelDownloadScreenState extends State<ModelDownloadScreen> {
  bool _handlingCompletion = false;

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? ReefPalette.darkMuted : ReefPalette.lightMuted;

    return Scaffold(
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final state = widget.controller.state;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const <Color>[
                        Color(0xFF081115),
                        Color(0xFF101D23),
                        Color(0xFF221915),
                      ]
                    : const <Color>[
                        Color(0xFFF4E2D5),
                        Color(0xFFF7F1EA),
                        Color(0xFFE9F1F2),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 900;
                  final panelWidth = compact ? constraints.maxWidth : 520.0;
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          children: <Widget>[
                            SizedBox(
                              width: panelWidth,
                              child: _HeroPanel(state: state, muted: muted),
                            ),
                            SizedBox(
                              width: panelWidth,
                              child: _MarketplacePanel(
                                state: state,
                                controller: widget.controller,
                                onPrimaryAction: _handlePrimaryAction,
                                onPause: widget.controller.pauseDownload,
                                onCancel: widget.controller.cancelDownload,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handlePrimaryAction() async {
    if (_handlingCompletion) {
      return;
    }

    final installedModel = await widget.controller.startDownload();
    if (installedModel == null || !mounted) {
      return;
    }

    _handlingCompletion = true;
    try {
      await widget.onModelReady();
    } finally {
      _handlingCompletion = false;
    }
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.state, required this.muted});

  final ModelDownloadState state;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedModel = state.selectedModel;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: ReefPalette.coral.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'MODEL MARKETPLACE',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: ReefPalette.coral,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'OpenReef needs a local model before the agent can boot.',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Download one model into secure app storage, then we will initialize it for on-device inference.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: muted,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _StatPill(
                  label: 'Device Free RAM',
                  value: state.deviceStats == null
                      ? 'Checking...'
                      : '${state.deviceStats!.freeRam.toStringAsFixed(1)} GB',
                ),
                _StatPill(
                  label: 'NPU Status',
                  value: state.deviceStats?.npuReady == true
                      ? 'Ready'
                      : 'CPU/GPU',
                ),
                _StatPill(
                  label: 'Selected',
                  value: selectedModel?.name ?? 'None',
                ),
              ],
            ),
            if (selectedModel != null) ...<Widget>[
              const SizedBox(height: 32),
              Text(
                selectedModel.bestFor,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                selectedModel.hardwareNotes ??
                    'Runs fully offline after download.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MarketplacePanel extends StatelessWidget {
  const _MarketplacePanel({
    required this.state,
    required this.controller,
    required this.onPrimaryAction,
    required this.onPause,
    required this.onCancel,
  });

  final ModelDownloadState state;
  final ModelDownloadController controller;
  final Future<void> Function() onPrimaryAction;
  final VoidCallback onPause;
  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedModel = state.selectedModel;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Choose a model',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your first run stays here until a model is fully available on disk.',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: 20),
            for (final model in controller.models) ...<Widget>[
              _ModelCard(
                descriptor: model,
                selected: state.selectedModel?.id == model.id,
                compatible: state.isCompatible(model),
                onTap: state.isDownloading
                    ? null
                    : () => controller.selectModel(model),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 8),
            if (selectedModel != null) ...<Widget>[
              Text(
                'Download progress',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 14,
                  value: state.status == ModelDownloadStatus.initializing
                      ? null
                      : state.progress.clamp(0, 1),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: <Widget>[
                  Text(
                    '${_formatBytes(state.downloadedBytes)} / ${_formatBytes(state.totalBytes > 0 ? state.totalBytes : selectedModel.expectedFileSizeBytes)}',
                  ),
                  Text(
                    state.bytesPerSecond > 0
                        ? '${_formatBytes(state.bytesPerSecond.round())}/s'
                        : 'Waiting for network',
                  ),
                  Text(
                    state.eta == null
                        ? 'ETA --'
                        : 'ETA ${_formatDuration(state.eta!)}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!state.isCompatible(selectedModel))
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    'This device may be under the recommended ${selectedModel.minRamGb.toStringAsFixed(0)} GB RAM target. Download is still allowed, but performance may degrade.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              if (state.errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  state.errorMessage!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: state.status == ModelDownloadStatus.initializing
                        ? null
                        : () => onPrimaryAction(),
                    icon: Icon(
                      state.status == ModelDownloadStatus.paused
                          ? Icons.play_arrow
                          : Icons.download,
                    ),
                    label: Text(switch (state.status) {
                      ModelDownloadStatus.paused => 'Resume Download',
                      ModelDownloadStatus.completed => 'Re-download Model',
                      ModelDownloadStatus.initializing =>
                        'Initializing Model',
                      _ => 'Download Model',
                    }),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        state.status == ModelDownloadStatus.downloading ||
                            state.status == ModelDownloadStatus.preparing
                        ? onPause
                        : null,
                    icon: const Icon(Icons.pause_circle_outline),
                    label: const Text('Pause'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isDownloading ? onCancel : null,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final fractionDigits = value >= 100 ? 0 : 1;
    return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    }
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.descriptor,
    required this.selected,
    required this.compatible,
    required this.onTap,
  });

  final ModelDescriptor descriptor;
  final bool selected;
  final bool compatible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? ReefPalette.coral.withValues(alpha: 0.10)
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: Key('model-card-${descriptor.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? ReefPalette.coral : theme.colorScheme.outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      descriptor.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (!compatible)
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(descriptor.bestFor, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _MetaChip(
                    label: _readableSize(descriptor.expectedFileSizeBytes),
                  ),
                  _MetaChip(label: '${descriptor.contextWindow ~/ 1000}k ctx'),
                  _MetaChip(
                    label: '${descriptor.minRamGb.toStringAsFixed(0)} GB RAM',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _readableSize(int bytes) {
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1) {
      return '${gb.toStringAsFixed(1)} GB';
    }
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
