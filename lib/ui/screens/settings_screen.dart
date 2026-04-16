import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/components/app_components.dart';
import 'package:openreef/models/embedding_model_manager.dart';
import 'package:openreef/models/model_descriptor.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.manager, super.key});
  final EmbeddingModelManager manager;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _tokenController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  bool _canInstall(EmbeddingModelReadiness readiness) {
    if (readiness.status == EmbeddingModelReadinessStatus.downloadable) {
      return true;
    }
    if (readiness.status == EmbeddingModelReadinessStatus.requiresAuth) {
      return readiness.hasToken;
    }
    if (readiness.status == EmbeddingModelReadinessStatus.failed) {
      return true;
    }
    return false;
  }

  String _installLabel(EmbeddingModelReadiness readiness) {
    return switch (readiness.status) {
      EmbeddingModelReadinessStatus.ready => 'Active',
      EmbeddingModelReadinessStatus.installed => 'Installed',
      EmbeddingModelReadinessStatus.downloading => 'Downloading...',
      EmbeddingModelReadinessStatus.failed => 'Retry Install',
      _ => 'Install',
    };
  }

  String _statusLabel(EmbeddingModelReadiness readiness) {
    return switch (readiness.status) {
      EmbeddingModelReadinessStatus.notConfigured =>
        'Choose a retrieval model.',
      EmbeddingModelReadinessStatus.downloadable => 'Available to install.',
      EmbeddingModelReadinessStatus.requiresAuth => 'Requires token.',
      EmbeddingModelReadinessStatus.downloading => 'Downloading...',
      EmbeddingModelReadinessStatus.installed => 'Ready for use.',
      EmbeddingModelReadinessStatus.ready => 'Active and ready for use.',
      EmbeddingModelReadinessStatus.failed => 'Installation failed.',
      _ => 'Status unknown',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.manager,
      builder: (context, _) {
        final readiness = widget.manager.readiness;
        final model = readiness.model;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            const AppPageHeader(
              title: 'Settings',
              subtitle: 'Configure your OpenReef application.',
            ),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semantic Memory Model',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Choose an embedding model to power context retrieval.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<ModelDescriptor>(
                    initialValue: model,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Model',
                    ),
                    items: widget.manager.models.map((m) {
                      return DropdownMenuItem(value: m, child: Text(m.name));
                    }).toList(),
                    onChanged: (selected) {
                      if (selected != null) {
                        widget.manager.selectModel(selected.id);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppBadge(
                    label: _statusLabel(readiness),
                    isSuccess:
                        readiness.status ==
                        EmbeddingModelReadinessStatus.installed,
                    isError:
                        readiness.status ==
                        EmbeddingModelReadinessStatus.failed,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (readiness.status ==
                          EmbeddingModelReadinessStatus.requiresAuth &&
                      !readiness.hasToken) ...[
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'HuggingFace Token',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: AppButton.secondary(
                        onPressed: _busy || model == null
                            ? null
                            : () async {
                                final token = _tokenController.text.trim();
                                if (token.isEmpty) return;
                                setState(() => _busy = true);
                                try {
                                  await widget.manager.saveHfToken(
                                    model.id,
                                    token,
                                  );
                                  _tokenController.clear();
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                        label: 'Save Token',
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerRight,
                    child: AppButton.primary(
                      onPressed: _canInstall(readiness) && !_busy
                          ? () async {
                              setState(() => _busy = true);
                              try {
                                await widget.manager.installSelectedModel();
                              } finally {
                                if (mounted) setState(() => _busy = false);
                              }
                            }
                          : null,
                      label: _installLabel(readiness),
                    ),
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
