import 'package:flutter/material.dart';

import 'package:openreef/models/model_download_controller.dart';
import 'package:openreef/models/model_download_state.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/components/app_components.dart';

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

  Future<void> _handlePrimaryAction() async {
    if (_handlingCompletion) return;
    final selectedModel = widget.controller.state.selectedModel;
    if (selectedModel != null && widget.controller.isActive(selectedModel)) {
      return;
    }
    final installedModel =
        selectedModel != null && widget.controller.isInstalled(selectedModel)
        ? await widget.controller.activateSelectedModel()
        : await widget.controller.startDownload();
    if (installedModel == null || !mounted) return;

    _handlingCompletion = true;
    try {
      await widget.onModelReady();
    } finally {
      _handlingCompletion = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final state = widget.controller.state;
        return Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    children: [
                      const AppPageHeader(
                        title: 'Model Initialization',
                        subtitle:
                            'OpenReef needs a local model before the agent can boot.',
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: _HeroPanel(state: state),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        child: _MarketplacePanel(
                          state: state,
                          controller: widget.controller,
                          onPrimaryAction: _handlePrimaryAction,
                          onPause: widget.controller.pauseDownload,
                          onCancel: widget.controller.cancelDownload,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.state});
  final ModelDownloadState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedModel = state.selectedModel;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Requirements',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              AppBadge(
                label:
                    'Free RAM: ${state.deviceStats?.freeRam.toStringAsFixed(1) ?? 'Checking...'} GB',
              ),
              AppBadge(
                label:
                    'NPU: ${state.deviceStats?.npuReady == true ? 'Ready' : 'CPU/GPU'}',
              ),
              AppBadge(label: 'Selected: ${selectedModel?.name ?? 'None'}'),
            ],
          ),
          if (selectedModel != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(selectedModel.bestFor, style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              selectedModel.hardwareNotes ??
                  'Runs fully offline after download.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
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

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedModel = state.selectedModel;
    final selectedInstalled =
        selectedModel != null && controller.isInstalled(selectedModel);
    final selectedActive =
        selectedModel != null && controller.isActive(selectedModel);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose a model',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          for (final model in controller.models) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              selected: selectedModel?.id == model.id,
              onTap: state.isDownloading
                  ? null
                  : () => controller.selectModel(model),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${model.expectedFileSizeBytes ~/ 1024 ~/ 1024} MB',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (!state.isCompatible(model))
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (selectedModel != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Download progress',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(
              value: state.status == ModelDownloadStatus.initializing
                  ? null
                  : state.progress.clamp(0, 1),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.lg,
              children: [
                Text(
                  '${_formatBytes(state.downloadedBytes)} / ${_formatBytes(state.totalBytes > 0 ? state.totalBytes : selectedModel.expectedFileSizeBytes)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  state.bytesPerSecond > 0
                      ? '${_formatBytes(state.bytesPerSecond.round())}/s'
                      : 'Waiting',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  state.eta == null
                      ? 'ETA --'
                      : 'ETA ${_formatDuration(state.eta!)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (!state.isCompatible(selectedModel)) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  'Your device may be under the recommended ${selectedModel.minRamGb.toStringAsFixed(0)} GB RAM target. Performance may be degraded.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.amber.shade800,
                  ),
                ),
              ),
            ],
            if (state.errorMessage != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                state.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton.primary(
                  onPressed:
                      state.status == ModelDownloadStatus.initializing ||
                          selectedActive
                      ? null
                      : () => onPrimaryAction(),
                  icon: selectedInstalled
                      ? Icons.check_circle_outline
                      : (state.status == ModelDownloadStatus.paused
                            ? Icons.play_arrow
                            : Icons.download),
                  label: switch (state.status) {
                    ModelDownloadStatus.paused => 'Resume',
                    ModelDownloadStatus.completed when selectedActive =>
                      'Active',
                    ModelDownloadStatus.completed when selectedInstalled =>
                      'Activate',
                    ModelDownloadStatus.initializing => 'Initializing',
                    _ when selectedActive => 'Active',
                    _ when selectedInstalled => 'Activate',
                    _ => 'Download',
                  },
                ),
                AppButton.secondary(
                  onPressed:
                      (state.status == ModelDownloadStatus.downloading ||
                          state.status == ModelDownloadStatus.preparing)
                      ? onPause
                      : null,
                  icon: Icons.pause_circle_outline,
                  label: 'Pause',
                ),
                AppButton.destructive(
                  onPressed: state.isDownloading ? onCancel : null,
                  icon: Icons.cancel_outlined,
                  label: 'Cancel',
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
