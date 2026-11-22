import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class NfcAttendanceApp extends ConsumerStatefulWidget {
  const NfcAttendanceApp({super.key});

  @override
  ConsumerState<NfcAttendanceApp> createState() => _NfcAttendanceAppState();
}

class _NfcAttendanceAppState extends ConsumerState<NfcAttendanceApp> {
  @override
  void initState() {
    super.initState();
    // Start the queue triggers (app start, resume, connectivity, 60 s).
    ref.read(queueTriggersProvider);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    ref.read(languageProvider).value = context.locale.languageCode;
  }

  @override
  Widget build(BuildContext context) {
    ref.read(languageProvider).value = context.locale.languageCode;
    return MaterialApp.router(
      title: 'TapIn360',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(arabic: context.locale.languageCode == 'ar'),
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
    );
  }
}
