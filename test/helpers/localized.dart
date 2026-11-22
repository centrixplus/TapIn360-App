import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nfc_attendance/app/theme.dart';
import 'package:nfc_attendance/core/l10n/app_language.dart';

/// Reads the real translation files synchronously (async file IO does not
/// complete inside widget tests).
class FileAssetLoader extends AssetLoader {
  const FileAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final text = File('assets/translations/${locale.languageCode}.json').readAsStringSync();
    return jsonDecode(text) as Map<String, dynamic>;
  }
}

/// Pumps [home] in the app's theme and language on a 390 × 844 phone
/// (the artboard size).
/// [settle] false: for screens that wait on real async work (FFI SQLite);
/// follow with `settle()` from app_scope.dart.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
  bool settle = true,
}) async {
  EasyLocalization.logger.enableBuildModes = [];
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await initializeDateFormatting();
  DateFormat.useNativeDigitsByDefaultFor('ar', false);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/translations',
      assetLoader: const FileAssetLoader(),
      startLocale: locale,
      fallbackLocale: fallbackLocale,
      saveLocale: false,
      useOnlyLangCode: true,
      child: Builder(
        builder: (context) => MaterialApp(
          theme: AppTheme.light(arabic: context.locale.languageCode == 'ar'),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: home,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}
