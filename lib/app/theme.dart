import 'package:flutter/material.dart';

import 'tokens.dart';

/// Material theme built from the TapIn360 tokens (light only). Arabic puts
/// IBM Plex Sans Arabic first; Latin falls through to it automatically.
abstract final class AppTheme {
  static ThemeData light({bool arabic = false}) {
    final family = arabic ? TapInFonts.arabic : TapInFonts.sans;
    final fallback = [arabic ? TapInFonts.sans : TapInFonts.arabic];
    final body = TapInText.body(arabic: arabic);
    final scheme = const ColorScheme.light(
      primary: TapInColors.primaryStrong,
      onPrimary: TapInColors.surfaceRaised,
      secondary: TapInColors.primary,
      onSecondary: TapInColors.surfaceRaised,
      error: TapInColors.danger,
      onError: TapInColors.surfaceRaised,
      surface: TapInColors.surfaceRaised,
      onSurface: TapInColors.ink,
      surfaceContainerHighest: TapInColors.surface,
      outline: TapInColors.borderStrong,
      outlineVariant: TapInColors.border,
    ).copyWith(surfaceTint: Colors.transparent);

    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(TapInRadius.md)),
    );
    const buttonText = TextStyle(fontSize: 16, fontWeight: FontWeight.w600);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: family,
      fontFamilyFallback: fallback,
      scaffoldBackgroundColor: TapInColors.bg,
      canvasColor: TapInColors.bg,
      dividerColor: TapInColors.border,
      splashFactory: InkRipple.splashFactory,
      textTheme: TextTheme(
        headlineLarge: TapInText.title(arabic: arabic),
        headlineSmall: TapInText.heading(arabic: arabic),
        titleLarge: TapInText.heading(arabic: arabic),
        titleMedium: body.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: body,
        bodyMedium: body,
        bodySmall: TapInText.bodySmall(arabic: arabic),
        labelLarge: buttonText,
        labelSmall: TapInText.label,
      ).apply(fontFamily: family, fontFamilyFallback: fallback),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TapInColors.primaryStrong,
          foregroundColor: TapInColors.surfaceRaised,
          disabledBackgroundColor: TapInColors.border,
          disabledForegroundColor: TapInColors.inkMuted,
          minimumSize: const Size(64, 52),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: TapInColors.surfaceRaised,
          foregroundColor: TapInColors.ink,
          side: const BorderSide(color: TapInColors.borderStrong),
          minimumSize: const Size(64, 52),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TapInColors.primaryStrong,
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: TapInColors.surfaceRaised,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(TapInRadius.sm)),
          borderSide: BorderSide(color: TapInColors.borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(TapInRadius.sm)),
          borderSide: BorderSide(color: TapInColors.borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(TapInRadius.sm)),
          borderSide: BorderSide(color: TapInColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(TapInRadius.sm)),
          borderSide: BorderSide(color: TapInColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(TapInRadius.sm)),
          borderSide: BorderSide(color: TapInColors.danger, width: 2),
        ),
        errorStyle: TextStyle(color: TapInColors.danger, fontSize: 14),
      ),
      cardTheme: const CardThemeData(
        color: TapInColors.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(TapInRadius.lg))),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: TapInColors.surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(TapInRadius.lg))),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: TapInColors.ink,
        contentTextStyle: TextStyle(color: TapInColors.surfaceRaised, fontSize: 15),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(TapInRadius.md))),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: TapInColors.primary),
      iconTheme: const IconThemeData(color: TapInColors.ink),
      appBarTheme: const AppBarTheme(
        backgroundColor: TapInColors.bg,
        foregroundColor: TapInColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}
