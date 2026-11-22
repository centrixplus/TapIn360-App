import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:uuid/uuid.dart';

import '../core/device/hardware_id.dart';
import '../core/device/system_channel.dart';
import '../core/nfc/launch_tag_channel.dart';
import '../core/queue/sqlite_tap_store.dart';
import '../core/storage/key_value_store.dart';
import '../core/storage/session_store.dart';
import 'providers.dart';

/// Everything that must be ready before the first frame: translations, date
/// symbols, the stored session, the tap database and an Android launch tag.
Future<List<Override>> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting();
  // Western digits in Arabic too, matching server messages ("09:02").
  DateFormat.useNativeDigitsByDefaultFor('ar', false);

  final secure = SecureKeyValueStore();
  final sessionStore = SessionStore(secure, newDeviceId: () => const Uuid().v4());
  final session = await sessionStore.load();

  final hardwareId = await HardwareIdReader(
    store: secure,
    readPlatformId: Platform.isAndroid ? SystemChannel().androidId : iosVendorId,
    cache: Platform.isIOS,
    fallbackId: session.deviceId,
  ).read();

  final taps = await SqliteTapStore.open();

  String? launchUid;
  try {
    launchUid = await LaunchTagChannel().takeLaunchTag();
  } catch (error) {
    debugPrint('Launch tag unavailable: $error');
  }

  return [
    sessionStoreProvider.overrideWithValue(sessionStore),
    initialSessionProvider.overrideWithValue(session),
    hardwareIdProvider.overrideWithValue(hardwareId),
    tapStoreProvider.overrideWithValue(taps),
    // A card that opened the app only counts when someone is logged in.
    pendingLaunchUidProvider.overrideWith((_) => session.isLoggedIn ? launchUid : null),
  ];
}
