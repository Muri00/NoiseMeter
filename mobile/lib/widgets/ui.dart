import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Карта на секция: заоблени ъгли, мека сянка и заглавие с икона.
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
  final IconData? icon;
  final Widget? trailing;
  final String? subtitle;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius + 4),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: isDark ? 1 : 0.5)),
        boxShadow: isDark ? null : softShadow,
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  IconBadge(icon: icon!),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title!, style: theme.textTheme.titleMedium),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

/// Малка икона в цветен заоблен квадрат - използва се в заглавията.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 36});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: c, size: size * 0.55),
    );
  }
}

/// Хапче със състояние (напр. "● ЗАПИС", "Готов").
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon, this.onDark = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.14) : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, size: icon == null ? 8 : 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: onDark ? Colors.white : color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Съобщение в цветна лента (грешка, информация, успех).
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.color, this.icon = Icons.info_outline, this.action});

  final String message;
  final Color? color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: c, fontWeight: FontWeight.w500))),
          ?action,
        ],
      ),
    );
  }
}

/// Логото на приложението: звукова вълна в заоблен квадрат.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: size * 0.58),
    );
  }
}

/// Стил за числата на шумомера - еднаква ширина на цифрите, за да не "трепкат".
const tabularFigures = [FontFeature.tabularFigures()];

/// Горна лента в цвета на градиентната заглавна част (за екраните с [BandedListView]).
AppBar bandAppBar({Widget? title, List<Widget>? actions, Widget? leading}) => AppBar(
      title: title,
      leading: leading,
      actions: actions,
      backgroundColor: AppColors.ink,
      foregroundColor: Colors.white,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      titleTextStyle: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
    );

/// Списък с градиентна заглавна лента отгоре; първите карти леко се застъпват с нея.
class BandedListView extends StatelessWidget {
  const BandedListView({super.key, this.header, required this.children, this.overlap = 32});

  final Widget? header;
  final List<Widget> children;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          decoration: const BoxDecoration(gradient: AppColors.bandGradient),
          padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + overlap),
          child: ReadableWidth(child: header ?? const SizedBox(height: 8)),
        ),
        // Transform измества картите нагоре, без да променя мястото, което заемат,
        // затова празното място отдолу служи и за долно отстояние.
        Transform.translate(
          offset: Offset(0, -overlap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ReadableWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ),
      ],
    );
  }
}

/// Заглавие и подзаглавие в бяло за градиентната лента.
class BandTitle extends StatelessWidget {
  const BandTitle({super.key, this.title, this.subtitle, this.bottom});

  final String? title;
  final String? subtitle;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Text(
            title!,
            style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
          ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
          ),
        if (bottom != null) ...[const SizedBox(height: 16), bottom!],
      ],
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
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: divider ? Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7))) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          // Две колони с еднаква ширина; стойността е подравнена вдясно.
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: valueColor),
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
