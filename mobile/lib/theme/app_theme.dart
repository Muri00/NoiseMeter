import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Дизайн система на METRAVA (Material 3): светъл фон, бели групи с тънка рамка,
/// син основен цвят и тъмен "инструментален" дисплей с циан показание.
abstract final class AppColors {
  static const primary = Color(0xFF0B4EA2); // избрани елементи, основни действия, превключватели
  static const accent = primary;
  static const brand = primary;
  static const ink = Color(0xFF11161A); // основен текст
  static const success = Color(0xFF1B8045); // в норма, успешна калибровка
  static const warning = Color(0xFFD97706); // извън лентата на микрофона, близо до нормата
  static const danger = Color(0xFFD32F2F); // запис, превишение, изтриване

  static const background = Color(0xFFF4F5F7);
  static const surface = Colors.white;
  static const surfaceHigh = Color(0xFFE9ECEF); // натиснато, заглавия на таблици
  static const line = Color(0xFFE3E6EA); // рамки и разделители (1 px)
  static const outline = Color(0xFFD3D8DE); // рамки на полетата
  static const textPrimary = ink;
  static const textSecondary = Color(0xFF5A626A);
  static const textTertiary = Color(0xFF8A9199);

  /// Фон на значките за състояние.
  static const successContainer = Color(0xFFE8F5E9);
  static const dangerContainer = Color(0xFFFFEBEE);
  static const warningContainer = Color(0xFFFFF4E5);

  /// Инструменталният дисплей.
  static const display = Color(0xFF1E2126);
  static const displayValue = Colors.white; // показанието на живо
  static const displayText = Colors.white;
  static const displayLabel = Color(0xFF8FA3B8);
  static const displayLine = Color(0xFF353A41);
  static const displayAccent = Color(0xFF4FC27A); // "Готов"

  /// Скалата на дисплея: синьо (тихо) - зелено - жълто - червено (шумно).
  static const scale = [Color(0xFF2F6BD8), Color(0xFF3DBE7A), Color(0xFFF0C93A), Color(0xFFE5533D)];

  /// Цвят според състоянието на калибровката на устройството.
  static Color forCalibration(String status) => switch (status) {
        'valid' => success,
        'due_soon' => warning,
        'expired' => danger,
        _ => warning,
      };

  /// Цвят според нивото на шума.
  static Color forLevel(double? db) {
    if (db == null) return textSecondary;
    if (db < 70) return success;
    if (db < 85) return warning;
    return danger;
  }
}

abstract final class AppFonts {
  static const sans = 'Golos';

  /// Без локалните (български) форми на кирилицата - до латински съкращения като LA,F
  /// "д" и "т" в тях се бъркат с g и m.
  static const noLocalForms = FontFeature('locl', 0);
}

/// Числови стойности (dB, Hz, време): цифри с еднаква ширина, за да не "трепкат".
TextStyle monoStyle(double size, {FontWeight weight = FontWeight.w400, Color? color, double? height}) => TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: size >= 40 ? -1.5 : 0,
      fontFeatures: const [FontFeature.tabularFigures(), AppFonts.noLocalForms],
    );

/// Заглавие на група ("Параметри", "Място и норми").
TextStyle sectionLabelStyle(BuildContext context) => TextStyle(
      fontFamily: AppFonts.sans,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: Theme.of(context).colorScheme.onSurface,
      fontFeatures: const [AppFonts.noLocalForms],
    );

abstract final class AppTheme {
  /// Групи и редове.
  static const radius = 12.0;

  /// Диалози, долни листове и инструменталният дисплей.
  static const cardRadius = 16.0;

  /// Чипове и бутони-хапчета.
  static const pillRadius = 20.0;

  static ThemeData light() => _build();

  static ThemeData navigation() => _build();

  static ThemeData _build() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCE7F7),
      onPrimaryContainer: Color(0xFF002D62),
      secondary: AppColors.primary,
      onSecondary: Colors.white,
      tertiary: AppColors.primary,
      onTertiary: Colors.white,
      error: AppColors.danger,
      onError: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.background,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: AppFonts.sans);
    final t = _withoutLocalForms(base.textTheme.apply(
      fontFamily: AppFonts.sans,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ));
    // Типографска скала: заглавие на екран 24, заглавие на група 16, редове 15, вторичен текст 13, етикети 11.
    final text = t.copyWith(
      headlineLarge: t.headlineLarge?.copyWith(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      headlineMedium: t.headlineMedium?.copyWith(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      headlineSmall: t.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleLarge: t.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w500),
      titleMedium: t.titleMedium?.copyWith(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w500),
      titleSmall: t.titleSmall?.copyWith(fontSize: 15, fontWeight: FontWeight.w500),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 20 / 15),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 13, height: 18 / 13),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      labelSmall: t.labelSmall?.copyWith(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w500, letterSpacing: 0.2),
    );

    const corners = BorderRadius.all(Radius.circular(radius));
    const shape = RoundedRectangleBorder(borderRadius: corners);
    const pill = StadiumBorder();
    const buttonSize = Size.fromHeight(48);
    const font = [AppFonts.noLocalForms];
    const buttonText = TextStyle(fontFamily: AppFonts.sans, fontSize: 15, fontWeight: FontWeight.w500, fontFeatures: font);
    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(borderRadius: corners, borderSide: BorderSide(color: color, width: width));

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        toolbarHeight: 64,
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
        titleTextStyle: text.headlineLarge?.copyWith(fontSize: 28, height: 34 / 28),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: corners, side: BorderSide(color: AppColors.line)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: field(AppColors.outline),
        enabledBorder: field(AppColors.outline),
        disabledBorder: field(AppColors.line),
        focusedBorder: field(AppColors.primary, 1.5),
        errorBorder: field(AppColors.danger),
        focusedErrorBorder: field(AppColors.danger, 1.5),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500),
        prefixIconColor: AppColors.textSecondary,
        suffixStyle: const TextStyle(color: AppColors.textSecondary),
        helperStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
      ),
      textSelectionTheme: const TextSelectionThemeData(cursorColor: AppColors.primary, selectionHandleColor: AppColors.primary),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textTertiary,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: pill,
          foregroundColor: AppColors.primary,
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.outline),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary, shape: pill, textStyle: buttonText),
      ),
      iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: shape)),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: shape,
          side: const BorderSide(color: AppColors.line),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textSecondary,
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          textStyle: const TextStyle(fontFamily: AppFonts.sans, fontWeight: FontWeight.w500, fontFeatures: font),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: AppColors.surfaceHigh,
        selectedColor: const Color(0xFFD5DAE0),
        checkmarkColor: scheme.onPrimaryContainer,
        labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
        side: const BorderSide(color: AppColors.textTertiary, width: 1.5),
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : null),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.surfaceHigh),
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.textTertiary),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.primary : AppColors.line),
      ),
      listTileTheme: const ListTileThemeData(
        shape: shape,
        iconColor: AppColors.textSecondary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontFamily: AppFonts.sans,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w500 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary,
            fontFeatures: font,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        minWidth: 72,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: const IconThemeData(color: AppColors.primary),
        unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
        selectedLabelTextStyle: text.labelMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w500),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: shape,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelLarge?.copyWith(
            color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.ink,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w500 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.primary : AppColors.textSecondary),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        dividerColor: AppColors.line,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: corners, side: BorderSide(color: AppColors.line)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: shape,
        backgroundColor: AppColors.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white, fontSize: 14),
        actionTextColor: const Color(0xFF82B2FF),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(cardRadius))),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleSize: Size(32, 4),
        dragHandleColor: AppColors.line,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius))),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
        textStyle: text.bodySmall?.copyWith(color: Colors.white),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(cardRadius))),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary, linearTrackColor: AppColors.line),
    );
  }
}

TextTheme _withoutLocalForms(TextTheme t) {
  TextStyle? f(TextStyle? s) => s?.copyWith(fontFeatures: const [AppFonts.noLocalForms]);
  return t.copyWith(
    displayLarge: f(t.displayLarge),
    displayMedium: f(t.displayMedium),
    displaySmall: f(t.displaySmall),
    headlineLarge: f(t.headlineLarge),
    headlineMedium: f(t.headlineMedium),
    headlineSmall: f(t.headlineSmall),
    titleLarge: f(t.titleLarge),
    titleMedium: f(t.titleMedium),
    titleSmall: f(t.titleSmall),
    bodyLarge: f(t.bodyLarge),
    bodyMedium: f(t.bodyMedium),
    bodySmall: f(t.bodySmall),
    labelLarge: f(t.labelLarge),
    labelMedium: f(t.labelMedium),
    labelSmall: f(t.labelSmall),
  );
}
