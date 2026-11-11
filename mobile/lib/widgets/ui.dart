import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Секция: удебелено заглавие над бял заоблен блок с тънка рамка.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    this.subtitle,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final String? title;

  /// Не се показва - оставено за съвместимост с екраните.
  final IconData? icon;
  final Widget? trailing;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: sectionLabelStyle(context)),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: Border.all(color: AppColors.line),
          ),
          padding: padding,
          child: child,
        ),
      ],
    );
  }
}

/// Група от редове направо на фона - удебелено заглавие и редове без рамка.
class RowGroup extends StatelessWidget {
  const RowGroup({super.key, this.title, required this.children, this.trailing});

  final String? title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
            child: Row(
              children: [
                Expanded(child: Text(title!, style: sectionLabelStyle(context))),
                ?trailing,
              ],
            ),
          ),
        Material(type: MaterialType.transparency, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
      ],
    );
  }
}

/// Ред: икона, етикет, стойност вдясно и стрелка, когато се натиска.
class ValueRow extends StatelessWidget {
  const ValueRow({
    super.key,
    required this.label,
    this.value,
    this.icon,
    this.onTap,
    this.valueColor,
    this.trailing,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 0, 10),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: AppColors.textSecondary),
                const SizedBox(width: 14),
              ],
              Text(label, style: theme.textTheme.bodyLarge),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value ?? '',
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(color: valueColor ?? AppColors.ink),
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (onTap != null && trailing == null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Ред с превключвател.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.icon, this.detail});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 0, 6),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22, color: AppColors.textSecondary),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  if (detail != null)
                    Text(detail!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Икона пред елемент от списък.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 36});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Icon(icon, color: color ?? AppColors.textSecondary, size: size * 0.62),
    );
  }
}

/// Състояние като цветен текст (напр. "В норма", "Превишение (+9.2 dB)", "Готов" върху дисплея).
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon, this.onDark = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: AppFonts.sans, fontWeight: FontWeight.w500, fontFeatures: [AppFonts.noLocalForms]);
    if (onDark) {
      return Text(label, style: style.copyWith(color: color, fontSize: 15));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 15, color: color), const SizedBox(width: 4)],
        Text(label, style: style.copyWith(color: color, fontSize: 14)),
      ],
    );
  }
}

/// Празно състояние: икона, заглавие, пояснение и действие.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Съобщение (грешка, предупреждение, успех): лек цветен фон, тънка рамка и незадължително заглавие.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.title, this.color, this.icon = Icons.info_outline, this.action});

  final String message;
  final String? title;
  final Color? color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.07), AppColors.surface),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: title == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(title!.toUpperCase(), style: theme.textTheme.labelLarge?.copyWith(color: c, letterSpacing: 0.3)),
                  ),
                Text(message, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14, color: AppColors.ink)),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Логото на приложението: звуковата вълна, а с [withName] - и надписът METRAVA под нея.
/// [size] е височината на логото.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64, this.withName = false});

  final double size;
  final bool withName;

  @override
  Widget build(BuildContext context) => Image.asset(
        withName ? 'assets/images/logo.png' : 'assets/images/logo_mark.png',
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'METRAVA',
      );
}

/// Стил за числата на шумомера - еднаква ширина на цифрите, за да не "трепкат".
const tabularFigures = [FontFeature.tabularFigures()];

/// Горна лента на вътрешните екрани.
AppBar bandAppBar({Widget? title, List<Widget>? actions, Widget? leading}) =>
    AppBar(title: title, leading: leading, actions: actions);

/// Списък от секции с еднакви отстояния.
class BandedListView extends StatelessWidget {
  const BandedListView({super.key, this.header, required this.children});

  final Widget? header;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        ReadableWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [?header, ...children],
          ),
        ),
      ],
    );
  }
}

/// Заглавие и подзаглавие на екран; [bottom] е под тях (филтри, избор на устройство).
class BandTitle extends StatelessWidget {
  const BandTitle({super.key, this.title, this.subtitle, this.bottom});

  final String? title;
  final String? subtitle;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (title == null && subtitle == null && bottom == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) Text(title!, style: theme.textTheme.headlineLarge?.copyWith(fontSize: 28)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            ),
          if (bottom != null) ...[if (title != null || subtitle != null) const SizedBox(height: 14), bottom!],
        ],
      ),
    );
  }
}

/// Ред "етикет - стойност" за таблици с информация.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.divider = true, this.valueColor});

  final String label;
  final String value;
  final bool divider;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: divider ? const Border(bottom: BorderSide(color: AppColors.line)) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          ),
          const SizedBox(width: 12),
          // Две колони с еднаква ширина; стойността е подравнена вдясно.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ограничава съдържанието до удобна за четене ширина и го центрира (таблет, широк екран).
class ReadableWidth extends StatelessWidget {
  const ReadableWidth({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Избор от списък в долен лист. Връща избраната стойност или null при отказ.
/// Всяка опция е (стойност, текст, пояснение или null).
Future<T?> showChoiceSheet<T>(
  BuildContext context, {
  required String title,
  required List<(T, String, String?)> options,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final (value, label, detail) in options)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                        title: Text(label),
                        subtitle: detail == null ? null : Text(detail),
                        trailing: value == selected ? const Icon(Icons.check_rounded, color: AppColors.accent) : null,
                        onTap: () => Navigator.pop(ctx, value),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Въвеждане на текст в долен лист. Връща новата стойност или null при отказ.
Future<String?> showTextSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initial = '',
  String? hint,
  TextInputType? keyboardType,
}) {
  final controller = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboardType,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: Text(confirmLabel)),
        ],
      ),
    ),
  );
}
