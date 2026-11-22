import 'package:flutter/material.dart';

/// TapIn360 design system tokens (tapin-ds tokens.json, light theme).
abstract final class TapInColors {
  static const bg = Color(0xFFF5F5F7);
  static const surface = Color(0xFFF0F0F3);
  static const surfaceRaised = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E5EA);
  static const borderStrong = Color(0xFF8E8E98);
  static const ink = Color(0xFF1F2937);

  /// Secondary text, only on [surfaceRaised].
  static const inkMuted = Color(0xFF6B7280);

  /// Icons, large text, focus ring, NFC motif — never under small white text.
  static const primary = Color(0xFF3B82F6);

  /// Filled buttons (white text), links, small blue text.
  static const primaryStrong = Color(0xFF2563EB);

  /// Fills with [ink] on top; never as text on white.
  static const success = Color(0xFF00C758);
  static const successStrong = Color(0xFF047A3A);
  static const danger = Color(0xFFB42318);
  static const warning = Color(0xFFB54708);
  static const warningTint = Color(0xFFFEF3C7);

  /// Camera preview well on the dark camera screen (AppCamera artboard).
  static const cameraWell = Color(0xFF3A4352);
}

abstract final class TapInRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
}

abstract final class TapInSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s4 = 16.0;
  static const s8 = 32.0;

  /// Side gutter used by the app artboards.
  static const gutter = 20.0;
}

abstract final class TapInFonts {
  static const sans = 'IBMPlexSans';
  static const arabic = 'IBMPlexSansArabic';
  static const mono = 'IBMPlexMono';
}

/// Type scale (tokens.json → type). Arabic gets taller lines (HomeAr artboard).
abstract final class TapInText {
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle title({bool arabic = false}) => TextStyle(
    fontSize: 32,
    height: (arabic ? 44 : 40) / 32,
    fontWeight: FontWeight.w600,
    color: TapInColors.ink,
  );

  static TextStyle heading({bool arabic = false}) => TextStyle(
    fontSize: 22,
    height: (arabic ? 30 : 28) / 22,
    fontWeight: FontWeight.w600,
    color: TapInColors.ink,
  );

  static TextStyle body({bool arabic = false}) => TextStyle(
    fontSize: 16,
    height: (arabic ? 26 : 24) / 16,
    fontWeight: FontWeight.w400,
    color: TapInColors.ink,
  );

  static TextStyle bodySmall({bool arabic = false}) => TextStyle(
    fontSize: 14,
    height: (arabic ? 22 : 20) / 14,
    fontWeight: FontWeight.w400,
    color: TapInColors.ink,
  );

  static const label = TextStyle(
    fontSize: 12,
    height: 16 / 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
    color: TapInColors.ink,
  );

  /// Company codes, card UIDs, phone IDs.
  static const code = TextStyle(
    fontFamily: TapInFonts.mono,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    color: TapInColors.ink,
  );

  /// Times and counts.
  static TextStyle tabular(TextStyle style) => style.copyWith(fontFeatures: _tabular);
}
