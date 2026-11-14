import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF080B12);
  static const Color surface = Color(0xFF111723);
  static const Color surfaceHigh = Color(0xFF182131);
  static const Color border = Color(0xFF243044);

  static const Color primary = Color(0xFF7C6CFF);
  static const Color primaryDeep = Color(0xFF5A48F0);
  static const Color accent = Color(0xFF2EE6B6);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF5A524);
  static const Color error = Color(0xFFF04452);

  static const Color textPrimary = Color(0xFFF3F5FA);
  static const Color textSecondary = Color(0xFF8E98AB);
  static const Color textMuted = Color(0xFF5D677A);

  static const LinearGradient brandGradient = LinearGradient(
    colors: <Color>[Color(0xFF8B7BFF), Color(0xFF5A48F0)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const List<Color> _categoryPalette = <Color>[
    Color(0xFF7C6CFF),
    Color(0xFF2EE6B6),
    Color(0xFFF5A524),
    Color(0xFFFF6B9A),
    Color(0xFF38BDF8),
    Color(0xFFA3E635),
    Color(0xFFFB923C),
    Color(0xFFE879F9),
  ];

  /// Stable color for a category ID.
  static Color forCategory(String categoryId) {
    if (categoryId.isEmpty) return textSecondary;
    var hash = 0;
    for (final unit in categoryId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _categoryPalette[hash % _categoryPalette.length];
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      error: AppColors.error,
      onSurface: AppColors.textPrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceHigh,
          disabledForegroundColor: AppColors.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dividerColor: AppColors.border,
    );
  }
}
