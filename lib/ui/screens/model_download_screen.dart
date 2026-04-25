import 'package:flutter/material.dart';

import 'package:openreef/models/model_descriptor.dart';
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
    if (selectedModel == null) return;

    final card = widget.controller.cardStateFor(selectedModel);
    switch (card.lifecycle) {
      case ModelCardLifecycle.discoverable:
      case ModelCardLifecycle.downloadable:
      case ModelCardLifecycle.failedDownload:
        await widget.controller.downloadSelectedModel();
      case ModelCardLifecycle.downloaded:
      case ModelCardLifecycle.failedInitialization:
        await widget.controller.initializeSelectedModel();
      case ModelCardLifecycle.initialized:
        final installedModel = await widget.controller.activateSelectedModel();
        if (installedModel == null || !mounted) return;
        _handlingCompletion = true;
        try {
          await widget.onModelReady();
        } finally {
          _handlingCompletion = false;
        }
      case ModelCardLifecycle.downloading:
      case ModelCardLifecycle.initializing:
      case ModelCardLifecycle.active:
      case ModelCardLifecycle.missingToken:
      case ModelCardLifecycle.unsupported:
      case ModelCardLifecycle.unavailable:
        return;
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
                        title: 'Model Marketplace',
                        subtitle:
                            'Browse, download, initialize, then activate a local generation model.',
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
                          primaryActionBusy: _handlingCompletion,
                          onPrimaryAction: _handlePrimaryAction,
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
                  'Runs fully offline after download and initialization.',
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
    required this.primaryActionBusy,
    required this.onPrimaryAction,
    required this.onCancel,
  });

  final ModelDownloadState state;
  final ModelDownloadController controller;
  final bool primaryActionBusy;
  final Future<void> Function() onPrimaryAction;
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

  IconData _primaryIcon(ModelCardLifecycle lifecycle) {
    return switch (lifecycle) {
      ModelCardLifecycle.downloaded ||
      ModelCardLifecycle.failedInitialization => Icons.play_circle_outline,
      ModelCardLifecycle.initialized => Icons.check_circle_outline,
      ModelCardLifecycle.active => Icons.verified,
      ModelCardLifecycle.failedDownload => Icons.refresh,
      ModelCardLifecycle.missingToken => Icons.key,
      ModelCardLifecycle.unsupported ||
      ModelCardLifecycle.unavailable => Icons.block,
      ModelCardLifecycle.initializing => Icons.hourglass_bottom,
      _ => Icons.download,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedModel = state.selectedModel;
    final selectedCard = selectedModel == null
        ? null
        : controller.cardStateFor(selectedModel);

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
          if (controller.models.isEmpty)
            Text(
              'No generation models are available in the registry.',
              style: theme.textTheme.bodyMedium,
            )
          else
            for (final model in controller.models) ...[
              _ModelListItem(
                model: model,
                card: controller.cardStateFor(model),
                selected: selectedModel?.id == model.id,
                disabled: state.isDownloading,
                formatBytes: _formatBytes,
                onTap: () => controller.selectModel(model),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          if (selectedModel != null && selectedCard != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              selectedModel.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppBadge(
                  label: selectedCard.isDownloaded
                      ? 'Downloaded'
                      : 'Not downloaded',
                ),
                AppBadge(
                  label: selectedCard.isInitialized
                      ? 'Initialized'
                      : 'Not initialized',
                ),
                AppBadge(label: selectedCard.isActive ? 'Active' : 'Inactive'),
                for (final capability in selectedCard.capabilityLabels)
                  AppBadge(label: capability),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              selectedCard.statusLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (selectedCard.reason != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                selectedCard.reason!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      selectedCard.lifecycle == ModelCardLifecycle.unsupported
                      ? Colors.amber.shade800
                      : theme.colorScheme.error,
                ),
              ),
            ],
            if (state.errorMessage != null &&
                selectedCard.reason != state.errorMessage) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                state.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (state.isDownloadInProgress) ...[
              const SizedBox(height: AppSpacing.md),
              LinearProgressIndicator(value: state.progress.clamp(0, 1)),
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
                        : 'Preparing',
                    style: theme.textTheme.bodySmall,
                  ),
                  Text(
                    state.eta == null
                        ? 'ETA unknown'
                        : 'ETA ${_formatDuration(state.eta!)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ] else if (state.isInitializing) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Initializing the downloaded model with the local runtime.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton.primary(
                  onPressed:
                      primaryActionBusy || !selectedCard.canRunPrimaryAction
                      ? null
                      : () => onPrimaryAction(),
                  icon: _primaryIcon(selectedCard.lifecycle),
                  label: selectedCard.primaryLabel,
                ),
                AppButton.destructive(
                  onPressed: state.isDownloadInProgress ? onCancel : null,
                  icon: Icons.cancel_outlined,
                  label: 'Cancel',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _AdvancedDetails(
              model: selectedModel,
              card: selectedCard,
              formatBytes: _formatBytes,
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelListItem extends StatelessWidget {
  const _ModelListItem({
    required this.model,
    required this.card,
    required this.selected,
    required this.disabled,
    required this.formatBytes,
    required this.onTap,
  });

  final ModelDescriptor model;
  final ModelCardState card;
  final bool selected;
  final bool disabled;
  final String Function(int bytes) formatBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      selected: selected,
      onTap: disabled ? null : onTap,
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
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${formatBytes(model.expectedFileSizeBytes)} · ${card.statusLabel}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final capability in card.capabilityLabels)
                      AppBadge(label: capability),
                  ],
                ),
              ],
            ),
          ),
          if (card.lifecycle == ModelCardLifecycle.unsupported ||
              card.lifecycle == ModelCardLifecycle.unavailable ||
              card.lifecycle == ModelCardLifecycle.missingToken)
            const Icon(Icons.info_outline, color: Colors.amber)
          else if (card.isActive)
            const Icon(Icons.verified, color: Colors.green)
          else if (card.isInitialized)
            const Icon(Icons.check_circle_outline)
          else if (card.isDownloaded)
            const Icon(Icons.download_done),
        ],
      ),
    );
  }
}

class _AdvancedDetails extends StatelessWidget {
  const _AdvancedDetails({
    required this.model,
    required this.card,
    required this.formatBytes,
  });

  final ModelDescriptor model;
  final ModelCardState card;
  final String Function(int bytes) formatBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sourceHost = Uri.tryParse(model.downloadUrl)?.host.isNotEmpty == true
        ? Uri.parse(model.downloadUrl).host
        : model.downloadUrl;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text('Advanced details', style: theme.textTheme.bodyMedium),
      children: [
        _DetailRow(label: 'Source', value: sourceHost),
        _DetailRow(label: 'Storage file', value: model.storageFileName),
        _DetailRow(label: 'Download URL', value: model.downloadUrl),
        if (model.tokenizerUrl != null)
          _DetailRow(label: 'Tokenizer URL', value: model.tokenizerUrl!),
        _DetailRow(
          label: 'Exact size',
          value: formatBytes(model.expectedFileSizeBytes),
        ),
        _DetailRow(
          label: 'Installed id',
          value: card.installedRecord?.modelId ?? 'Not installed',
        ),
        _DetailRow(label: 'Vision', value: 'Not declared by model metadata'),
        _DetailRow(label: 'Audio', value: 'Not declared by model metadata'),
        _DetailRow(label: 'Reasoning', value: 'Not declared by model metadata'),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
