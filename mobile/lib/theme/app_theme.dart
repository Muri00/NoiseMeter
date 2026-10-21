import 'package:flutter/material.dart';

/// Цветова схема "измервателен уред": тъмносин и петролен основен цвят,
/// кехлибарен акцент (спектър, запис) и ясни цветове за състоянията.
abstract final class AppColors {
  static const ink = Color(0xFF0B2545); // тъмносин - заглавни части, градиенти
  static const primary = Color(0xFF0B6E99); // петролено син - основни действия
  static const accent = Color(0xFFF2A541); // кехлибарен - спектър, акценти
  static const success = Color(0xFF2E9E6A);
  static const warning = Color(0xFFE08A1E);
  static const danger = Color(0xFFD64545);

  static const background = Color(0xFFF3F6FA);
  static const surface = Colors.white;
  static const outline = Color(0xFFE2E8F0);
  static const textPrimary = Color(0xFF14213D);
  static const textSecondary = Color(0xFF5B6B82);

  static const darkBackground = Color(0xFF0D1321);
  static const darkSurface = Color(0xFF151D2E);
  static const darkSurfaceHigh = Color(0xFF1D283D);

  /// Градиент за заглавните части (вход, меню, основното показание).
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [ink, Color(0xFF0E4D74), primary],
  );

  /// Вертикален градиент за заглавната лента на вътрешните екрани. Започва с [ink],
  /// за да продължава плавно горната лента (AppBar), която е в същия цвят.
  static const bandGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ink, Color(0xFF0E4D74), Color(0xFF0D5F86)],
  );

  /// Цвят според състоянието на калибровката на устройството.
  static Color forCalibration(String status) => switch (status) {
        'valid' => success,
        'due_soon' => warning,
        'expired' => danger,
        _ => warning,
      };

  /// Цвят според нивото на шума - за бърз визуален ориентир.
  static Color forLevel(double? db) {
    if (db == null) return textSecondary;
    if (db < 55) return success;
    if (db < 70) return const Color(0xFF8BB43A);
    if (db < 85) return warning;
    return danger;
  }
}

/// Мека, едва забележима сянка за картите.
const softShadow = [
  BoxShadow(color: Color(0x140B2545), blurRadius: 18, offset: Offset(0, 6)),
  BoxShadow(color: Color(0x0A0B2545), blurRadius: 4, offset: Offset(0, 1)),
];

abstract final class AppTheme {
  static const radius = 16.0;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFF5EB8E0) : AppColors.primary,
      onPrimary: isDark ? AppColors.ink : Colors.white,
      secondary: isDark ? const Color(0xFF9FB4D3) : AppColors.ink,
      tertiary: AppColors.accent,
      error: AppColors.danger,
      surface: isDark ? AppColors.darkSurface : AppColors.surface,
      onSurface: isDark ? const Color(0xFFE6ECF5) : AppColors.textPrimary,
      onSurfaceVariant: isDark ? const Color(0xFF9AA8BD) : AppColors.textSecondary,
      surfaceContainerLowest: isDark ? AppColors.darkBackground : AppColors.background,
      surfaceContainerLow: isDark ? AppColors.darkSurface : const Color(0xFFF8FAFC),
      surfaceContainer: isDark ? AppColors.darkSurfaceHigh : const Color(0xFFEFF3F8),
      surfaceContainerHigh: isDark ? AppColors.darkSurfaceHigh : const Color(0xFFE9EEF5),
      outlineVariant: isDark ? const Color(0xFF2A3650) : AppColors.outline,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)));
    const buttonSize = Size.fromHeight(52);

    return base.copyWith(
      scaffoldBackgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 2,
        shadowColor: const Color(0x330B2545),
        margin: EdgeInsets.zero,
        shape: shape.copyWith(side: BorderSide(color: scheme.outlineVariant.withValues(alpha: isDark ? 1 : 0.6))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceHigh : const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        // Подчертана рамка със заоблени ъгли: етикетът остава вътре в полето.
        border: const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        disabledBorder: const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: UnderlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: AppColors.danger, width: 2),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixStyle: TextStyle(color: scheme.onSurfaceVariant),
        helperStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: scheme.outlineVariant, width: 1.4),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          side: BorderSide(color: scheme.outlineVariant),
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        backgroundColor: scheme.surface,
        selectedColor: scheme.primary.withValues(alpha: 0.14),
        labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        iconColor: scheme.onSurfaceVariant,
      ),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? const Icon(Icons.check, size: 14) : null,
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelLarge?.copyWith(
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurface,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
