import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/api/api_models.dart';
import '../../core/location/location_tracker.dart';
import '../../core/photo/camera_plugin_session.dart';
import '../../core/photo/mlkit_face_finder.dart';
import '../../core/photo/photo_compressor.dart';
import '../../core/photo/punch_photo.dart';
import '../../core/nfc/nfc_reader.dart';
import '../../core/tap/tap_outcome.dart';
import '../photo/photo_capture_screen.dart';
import 'home_actions.dart';
import 'home_controller.dart';
import 'home_view.dart';

/// Home lifecycle (spec §6.2, §6.4): while Home is visible and the app is in
/// the foreground the GPS stream runs and, on Android, NFC reader mode is on
/// (restarted on every resume because the OS turns it off on pause). Cards
/// that launch/resume the app (Android) are treated as taps.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver implements HomeActions {
  bool _visible = true;
  bool _askedLocation = false;
  Future<void> _lifecycle = Future.value();
  DateTime? _lastHintAt;

  late final NfcReader _reader;
  late final LocationTracker _tracker;

  HomeController get _controller => ref.read(homeControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _reader = ref.read(nfcReaderProvider);
    _tracker = ref.read(locationTrackerProvider);
    WidgetsBinding.instance.addObserver(this);
    ref.read(launchTagChannelProvider).listen(_onLaunchTag);
    WidgetsBinding.instance.addPostFrameCallback((_) => _activate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopNfc());
    unawaited(_tracker.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_visible) return;
    if (state == AppLifecycleState.resumed) _activate();
    if (state == AppLifecycleState.paused) _deactivate();
  }

  /// Serialised so a resume during a permission prompt cannot interleave.
  void _activate() => _lifecycle = _lifecycle.then((_) => _doActivate());
  void _deactivate() => _lifecycle = _lifecycle.then((_) => _doDeactivate());

  Future<void> _doActivate() async {
    if (!mounted || !_visible) return;
    final controller = _controller;
    unawaited(controller.refreshWaiting());
    unawaited(controller.refreshStatus());
    await controller.checkLocation(request: !_askedLocation);
    _askedLocation = true;
    await _startNfc();
    if (!mounted) return;
    final pending = ref.read(pendingLaunchUidProvider);
    if (pending != null) {
      ref.read(pendingLaunchUidProvider.notifier).state = null;
      unawaited(_onUid(pending));
    }
  }

  Future<void> _doDeactivate() async {
    await _stopNfc();
    await _tracker.stop();
  }

  Future<void> _startNfc() async {
    final NfcAvailability availability;
    try {
      availability = await _reader.availability();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _controller.setNfc(availability);
    if (Platform.isIOS || availability != NfcAvailability.enabled) return;
    await _stopNfc();
    try {
      await _reader.start(onTag: _onTag, onError: _onNfcError);
    } catch (error) {
      _onNfcError(error.toString());
    }
  }

  Future<void> _stopNfc() async {
    try {
      await _reader.stop();
    } catch (_) {
      // No session running.
    }
  }

  Future<void> _onTag(NfcTag tag) async {
    final uid = uidOf(tag);
    if (Platform.isIOS) {
      await _reader.stop(
        alertMessageIos: uid == null ? null : 'home.card_read'.tr(),
        errorMessageIos: uid == null ? 'home.unreadable_card'.tr() : null,
      );
    }
    if (uid == null) {
      _snack('home.unreadable_card'.tr());
      return;
    }
    await _onUid(uid);
  }

  void _onLaunchTag(String uid) {
    if (mounted && _visible) unawaited(_onUid(uid));
  }

  Future<void> _onUid(String uid) async {
    if (!mounted || !_visible) return;
    final outcome = await _controller.onCardRead(uid, takePhoto: _takePhoto);
    if (outcome is TapNeedsAction) _hint('home.need_action'.tr());
  }

  /// Full-screen front camera (spec §15.3). Home stays active underneath, so
  /// the GPS stream keeps running while the photo is taken.
  Future<PunchPhoto?> _takePhoto() async {
    if (!mounted) return null;
    return Navigator.of(context).push<PunchPhoto?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoCaptureScreen(
          cardReadAt: DateTime.now(),
          camera: CameraPluginSession(),
          faceFinder: MlKitFaceFinder(),
          encode: compressPhotoInBackground,
          onOpenSettings: ref.read(locationGatewayProvider).openAppSettings,
        ),
      ),
    );
  }

  void _onNfcError(String message) => _snack('home.nfc_error'.tr(namedArgs: {'message': message}));

  /// Android re-reads a held card every second; show the hint at most every 3 s.
  void _hint(String text) {
    final now = DateTime.now();
    final last = _lastHintAt;
    if (last != null && now.difference(last) < const Duration(seconds: 3)) return;
    _lastHintAt = now;
    _snack(text);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openPage(String path) async {
    _visible = false;
    _deactivate();
    await context.push<void>(path);
    if (!mounted) return;
    _visible = true;
    _activate();
  }

  // HomeActions

  @override
  void scan() {
    unawaited(
      _reader
          .start(onTag: _onTag, onError: _onNfcError, alertMessageIos: 'home.ios_sheet'.tr())
          .catchError((Object error) => _onNfcError(error.toString())),
    );
  }

  @override
  void selectAction(PunchAction action) {
    _controller.selectAction(action);
    if (Platform.isIOS) scan();
  }

  @override
  void cancelAction() => _controller.cancelAction();

  @override
  void openHistory() => _openPage(Routes.history);

  @override
  void openSettings() => _openPage(Routes.settings);

  @override
  void allowLocation() => _controller.checkLocation(request: true);

  @override
  void openAppSettings() => ref.read(locationGatewayProvider).openAppSettings();

  @override
  void openLocationSettings() => ref.read(locationGatewayProvider).openLocationSettings();

  @override
  void openNfcSettings() => ref.read(systemChannelProvider).openNfcSettings();

  @override
  void logIn() => context.go(Routes.login);

  @override
  void dismissResult() => _controller.dismissResult();

  @override
  Future<void> refresh() => _controller.refresh();

  /// Debug builds only (the motif's long-press): the wall card used in tests.
  @override
  void simulateTap() {
    if (kDebugMode) unawaited(_onUid('04DB8FE23B1590'));
  }

  @override
  Widget build(BuildContext context) {
    return HomeView(state: ref.watch(homeControllerProvider), actions: this);
  }
}
