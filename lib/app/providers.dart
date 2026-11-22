import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api/attendance_api.dart';
import '../core/config/tapin_config.dart';
import '../core/directory/directory_api.dart';
import '../core/device/device_descriptor.dart';
import '../core/device/local_ip.dart';
import '../core/device/system_channel.dart';
import '../core/location/location_gateway.dart';
import '../core/location/location_tracker.dart';
import '../core/nfc/launch_tag_channel.dart';
import '../core/nfc/nfc_reader.dart';
import '../core/queue/punch_queue.dart';
import '../core/queue/queue_triggers.dart';
import '../core/queue/tap_store.dart';
import '../core/session/session.dart';
import '../core/session/session_controller.dart';
import '../core/storage/key_value_store.dart';
import '../core/storage/session_store.dart';
import '../core/tap/tap_service.dart';
import '../features/home/home_controller.dart';
import '../features/company/qr_scan_screen.dart';
import '../features/home/home_state.dart';

const _uuid = Uuid();

// Overridden in bootstrap.dart.
final initialSessionProvider = Provider<Session>((_) => throw UnimplementedError());
final tapStoreProvider = Provider<TapStore>((_) => throw UnimplementedError());

/// This phone's hardware ID (spec §14), read once at start.
final hardwareIdProvider = Provider<String>((_) => throw UnimplementedError());

/// UID of the card that cold-started the app (Android), consumed by Home.
final pendingLaunchUidProvider = StateProvider<String?>((_) => null);

/// Current UI language code, sent as `Accept-Language`. Updated by the app
/// widget from easy_localization (a plain notifier, so it can be set during
/// build without a Riverpod state change).
final languageProvider = Provider<ValueNotifier<String>>((ref) {
  final notifier = ValueNotifier('en');
  ref.onDispose(notifier.dispose);
  return notifier;
});

final sessionStoreProvider = Provider<SessionStore>(
  (_) => SessionStore(SecureKeyValueStore(), newDeviceId: () => _uuid.v4()),
);

/// Server URL + token used by the API client. Kept outside the provider graph:
/// the session controller depends on the API, so the API must not read the
/// session provider (Riverpod rejects the cycle). The controller updates it.
class ApiCredentials {
  String? serverUrl;
  String? token;

  void update(Session session) {
    serverUrl = session.serverUrl;
    token = session.token;
  }
}

final apiCredentialsProvider = Provider<ApiCredentials>(
  (ref) => ApiCredentials()..update(ref.watch(initialSessionProvider)),
);

final apiProvider = Provider<AttendanceApi>((ref) {
  final credentials = ref.watch(apiCredentialsProvider);
  return AttendanceApi(
    dio: createApiDio(),
    baseUrl: () => credentials.serverUrl,
    token: () => credentials.token,
    language: () => ref.read(languageProvider).value,
  );
});

final punchQueueProvider = Provider<PunchQueue>((ref) {
  return PunchQueue(
    store: ref.watch(tapStoreProvider),
    send: ref.watch(apiProvider).punch,
    paused: !ref.read(initialSessionProvider).isLoggedIn || ref.read(initialSessionProvider).accessSwitchedOff,
  );
});

final sessionProvider = StateNotifierProvider<SessionController, Session>((ref) {
  final initial = ref.watch(initialSessionProvider);
  final queue = ref.watch(punchQueueProvider);
  final credentials = ref.watch(apiCredentialsProvider);
  final controller = SessionController(
    initial: initial,
    storage: ref.watch(sessionStoreProvider),
    api: ref.watch(apiProvider),
    queue: queue,
    taps: ref.watch(tapStoreProvider),
    device: () => describeDevice(initial.deviceId, ref.read(hardwareIdProvider)),
  );
  // Fires now and on every change, before anything else reacts.
  controller.addListener(credentials.update);
  // 401 from the queue → logout locally and pause; 403 access_switched_off → block.
  queue.onUnauthorized = controller.expire;
  queue.onSwitchedOff = controller.switchOff;
  return controller;
});

final queueTriggersProvider = Provider<QueueTriggers>((ref) {
  final triggers = QueueTriggers(
    flush: ref.watch(punchQueueProvider).flush,
    connectivity: Connectivity().onConnectivityChanged,
  )..start();
  ref.onDispose(triggers.dispose);
  return triggers;
});

final locationGatewayProvider = Provider<LocationGateway>((_) => LocationGateway());

final locationTrackerProvider = Provider<LocationTracker>((ref) {
  final tracker = LocationTracker(openStream: ref.watch(locationGatewayProvider).positions);
  ref.onDispose(tracker.dispose);
  return tracker;
});

final tapServiceProvider = Provider<TapService>((ref) {
  return TapService(
    store: ref.watch(tapStoreProvider),
    queue: ref.watch(punchQueueProvider),
    fixForTap: ref.watch(locationTrackerProvider).fixForTap,
    newUuid: () => _uuid.v4(),
    employeeId: () => ref.read(sessionProvider).employee?.id,
    acceptsTaps: () {
      final session = ref.read(sessionProvider);
      return !session.loggingOut && !session.accessSwitchedOff;
    },
    hardwareId: ref.watch(hardwareIdProvider),
    localIp: localIpv4,
  );
});

final nfcReaderProvider = Provider<NfcReader>((_) => NfcReader());

/// TapIn360 master directory (company code → API base).
final directoryApiProvider = Provider<DirectoryApi>((ref) {
  return DirectoryApi(
    dio: createApiDio(),
    masterUrl: tapinMasterUrl,
    language: () => ref.read(languageProvider).value,
  );
});

/// Opens the QR scanner and returns the company code, or null (cancelled).
/// Overridden in widget tests.
final qrScannerProvider = Provider<Future<String?> Function(BuildContext context)>((_) => scanCompanyQr);
final launchTagChannelProvider = Provider<LaunchTagChannel>((_) => LaunchTagChannel());
final systemChannelProvider = Provider<SystemChannel>((_) => SystemChannel());

final homeControllerProvider = StateNotifierProvider.autoDispose<HomeController, HomeState>((ref) {
  final session = ref.read(sessionProvider);
  final controller = HomeController(
    initial: HomeState(
      employeeName: session.employee?.name ?? '',
      punchMode: session.punchMode,
      isIos: Platform.isIOS,
      loggedIn: session.isLoggedIn,
      accessSwitchedOff: session.accessSwitchedOff,
      photoRequired: session.photoRequired,
      companyName: companyNameOf(session),
    ),
    api: ref.watch(apiProvider),
    session: ref.watch(sessionProvider.notifier),
    taps: ref.watch(tapServiceProvider),
    store: ref.watch(tapStoreProvider),
    queue: ref.watch(punchQueueProvider),
    tracker: ref.watch(locationTrackerProvider),
    location: ref.watch(locationGatewayProvider),
  );
  ref.listen<Session>(sessionProvider, (_, next) => controller.applySession(next));
  return controller;
});
