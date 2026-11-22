import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/l10n/app_language.dart';

Future<void> main() async {
  final overrides = await bootstrap();
  runApp(
    EasyLocalization(
      supportedLocales: supportedLocales,
      path: 'assets/translations',
      fallbackLocale: fallbackLocale,
      useOnlyLangCode: true,
      child: ProviderScope(overrides: overrides, child: const NfcAttendanceApp()),
    ),
  );
}
