import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';
import 'package:openreef/ui/components/app_components.dart';
import 'package:openreef/ui/automation_builder_screen.dart';
import 'package:openreef/ui/automation_controller.dart';
import 'package:openreef/ui/automation_models.dart';

class AutomationScreen extends StatelessWidget {
  const AutomationScreen({required this.controller, super.key});

  final AutomationController controller;

  Future<void> _openBuilder(
    BuildContext context,
    AutomationEditorDraft draft,
  ) async {
    final result = await Navigator.of(context).push<AutomationEditorDraft>(
      MaterialPageRoute<AutomationEditorDraft>(
        builder: (context) => AutomationBuilderScreen(
          controller: controller,
          initialDraft: draft,
        ),
      ),
    );
    if (result == null || !context.mounted) {
      return;
    }
    try {
      await controller.saveFromDraft(result);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Automation was not saved: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.isLoading) {
          return const StateView.loading();
        }

        final items = controller.allItems;

        return Column(
          children: [
            AppPageHeader(
              title: 'Automations',
              subtitle: 'Scheduled and repeating background tasks.',
              actions: [
                AppButton.primary(
                  onPressed: () => _openBuilder(
                    context,
                    controller.draftForCreate(AutomationEditorKind.schedule),
                  ),
                  icon: Icons.add,
                  label: 'Add Automation',
                ),
              ],
            ),
            Expanded(
              child: items.isEmpty
                  ? const StateView.empty(
                      title: 'No Active Automations',
                      subtitle:
                          'Add an automation to run tasks in the background.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final vm = items[index];
                        final isError =
                            vm.driftState ==
                            AutomationDriftState.persistedNotRegistered;

                        return AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      vm.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  AppBadge(
                                    label: vm.runtimeStatusLabel,
                                    isSuccess: vm.enabled && !isError,
                                    isError: isError,
                                  ),
                                  Switch(
                                    value: vm.enabled,
                                    onChanged: (val) {
                                      controller.setEnabled(vm.id, val);
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                vm.summary,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Row(
                                children: [
                                  Icon(
                                    Icons.schedule,
                                    size: 16,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    vm.subtypeLabel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  const Spacer(),
                                  if (vm.canEdit)
                                    AppButton.secondary(
                                      onPressed: () => _openBuilder(
                                        context,
                                        controller.draftForEdit(vm.id),
                                      ),
                                      icon: Icons.edit_outlined,
                                      label: 'Edit',
                                    ),
                                  if (vm.canEdit)
                                    const SizedBox(width: AppSpacing.sm),
                                  if (vm.canDelete)
                                    AppButton.destructive(
                                      onPressed: () =>
                                          AppComponents.showDestructiveDialog(
                                            context: context,
                                            title: 'Delete Automation',
                                            content:
                                                'Are you sure you want to delete "${vm.title}"?',
                                            confirmLabel: 'Delete',
                                            onConfirm: () =>
                                                controller.deleteTrigger(vm.id),
                                          ),
                                      label: 'Delete',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
