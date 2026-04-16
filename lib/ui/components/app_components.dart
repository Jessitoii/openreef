import 'package:flutter/material.dart';
import 'package:openreef/ui/app_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.selected = false,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: selected ? ReefPalette.coral.withValues(alpha: 0.1) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected ? BorderSide(color: ReefPalette.coral) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

class AppButton extends StatelessWidget {
  const AppButton.primary({
    required this.onPressed,
    required this.label,
    this.icon,
    super.key,
  }) : _type = _AppButtonType.primary;

  const AppButton.secondary({
    required this.onPressed,
    required this.label,
    this.icon,
    super.key,
  }) : _type = _AppButtonType.secondary;

  const AppButton.destructive({
    required this.onPressed,
    required this.label,
    this.icon,
    super.key,
  }) : _type = _AppButtonType.destructive;

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final _AppButtonType _type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    switch (_type) {
      case _AppButtonType.primary:
        if (icon != null) {
          return FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
        }
        return FilledButton(onPressed: onPressed, child: Text(label));
      
      case _AppButtonType.secondary:
        if (icon != null) {
          return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
        }
        return OutlinedButton(onPressed: onPressed, child: Text(label));
      
      case _AppButtonType.destructive:
        final style = OutlinedButton.styleFrom(
          foregroundColor: theme.colorScheme.error,
          side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
        );
        if (icon != null) {
          return OutlinedButton.icon(style: style, onPressed: onPressed, icon: Icon(icon), label: Text(label));
        }
        return OutlinedButton(style: style, onPressed: onPressed, child: Text(label));
    }
  }
}

enum _AppButtonType { primary, secondary, destructive }

class AppBadge extends StatelessWidget {
  const AppBadge({
    required this.label,
    this.isSuccess = false,
    this.isError = false,
    super.key,
  });

  final String label;
  final bool isSuccess;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color bgColor = theme.colorScheme.surfaceContainerHighest;
    Color fgColor = theme.colorScheme.onSurfaceVariant;
    
    if (isSuccess) {
      bgColor = ReefPalette.success.withValues(alpha: 0.15);
      fgColor = ReefPalette.success;
    } else if (isError) {
      bgColor = theme.colorScheme.error.withValues(alpha: 0.15);
      fgColor = theme.colorScheme.error;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: fgColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: actions,
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ]
        ],
      ),
    );
  }
}

class StateView extends StatelessWidget {
  const StateView.error({
    required this.title,
    required this.subtitle,
    super.key,
  }) : _style = _StateViewStyle.error;

  const StateView.empty({
    required this.title,
    this.subtitle,
    super.key,
  }) : _style = _StateViewStyle.empty;

  const StateView.loading({
    super.key,
  }) : _style = _StateViewStyle.loading, title = '', subtitle = null;

  final String title;
  final String? subtitle;
  final _StateViewStyle _style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_style == _StateViewStyle.loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isError = _style == _StateViewStyle.error;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.inbox_outlined,
              size: 48,
              color: isError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: isError ? theme.colorScheme.error : null,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

enum _StateViewStyle { empty, error, loading }

class AppComponents {
  static Future<bool?> showDestructiveDialog({
    required BuildContext context,
    required String title,
    required String content,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          AppButton.secondary(
            onPressed: () => Navigator.of(context).pop(false),
            label: 'Cancel',
          ),
          AppButton.destructive(
            onPressed: () async {
              await onConfirm();
              if (context.mounted) Navigator.of(context).pop(true);
            },
            label: confirmLabel,
          ),
        ],
      ),
    );
  }

  static Future<T?> showStandardSheet<T>({
    required BuildContext context,
    required Widget child,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: AppSpacing.md,
            right: AppSpacing.md,
            top: AppSpacing.sm,
          ),
          child: child,
        ),
      ),
    );
  }
}
