import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

import '../../core/api/api_models.dart';
import '../../core/api/api_outcome.dart';
import '../../core/api/attendance_api.dart';
import '../../core/location/location_gateway.dart';
import '../../core/location/location_tracker.dart';
import '../../core/photo/punch_photo.dart';
import '../../core/queue/punch_queue.dart';
import '../../core/queue/tap_record.dart';
import '../../core/queue/tap_store.dart';
import '../../core/session/session.dart';
import '../../core/session/session_controller.dart';
import '../../core/tap/tap_outcome.dart';
import '../../core/tap/tap_service.dart';
import 'home_state.dart';

/// Home screen logic: status, banners, GPS indicator, waiting badge, manual
/// selection and card reads (spec §6.1–§6.2).
class HomeController extends StateNotifier<HomeState> {
  HomeController({
    required HomeState initial,
    required this._api,
    required this._session,
    required this._taps,
    required this._store,
    required this._queue,
    required this._tracker,
    required this._location,
  }) : super(initial) {
    _storeChanges = _store.changes.listen((_) => refreshWaiting());
    _tracker.addListener(_onGps);
    _onGps();
  }

  final AttendanceApi _api;
  final SessionController _session;
  final TapService _taps;
  final TapStore _store;
  final PunchQueue _queue;
  final LocationTracker _tracker;
  final LocationGateway _location;
  late final StreamSubscription<void> _storeChanges;

  void applySession(Session session) {
    state = state.copyWith(
      // Logging out: taps are refused from the first moment (§6.3).
      loggedIn: session.isLoggedIn && !session.loggingOut,
      accessSwitchedOff: session.accessSwitchedOff,
      employeeName: session.employee?.name ?? state.employeeName,
      punchMode: session.punchMode,
      photoRequired: session.photoRequired,
      companyName: companyNameOf(session),
    );
  }

  Future<void> refreshStatus() async {
    if (!state.loggedIn) return;
    final outcome = await _api.status();
    if (!mounted) return;
    switch (outcome) {
      case ApiOk(:final value):
        state = state.copyWith(
          statusKind: value.state == AttendanceState.checkedIn ? StatusKind.checkedIn : StatusKind.checkedOut,
          since: value.since,
          site: value.site,
        );
        await _session.applyStatus(value);
      case ApiRejected(isUnauthorized: true):
        await _session.expire();
      case ApiRejected(isSwitchedOff: true):
        state = state.copyWith(statusKind: StatusKind.unavailable);
        await _session.switchOff();
      case ApiRejected() || ApiUnreachable():
        state = state.copyWith(statusKind: StatusKind.unavailable);
    }
  }

  /// Waiting badge and the "Last tap" line.
  Future<void> refreshWaiting() async {
    final int count;
    final TapRecord? last;
    try {
      count = await _store.waitingCount();
      last = await _store.lastSent();
    } catch (_) {
      return; // Store closed (app shutting down); the badge refreshes next time.
    }
    if (!mounted) return;
    state = state.copyWith(
      waitingCount: count,
      lastTapAt: last?.tappedAt ?? last?.createdAt,
      lastTapSite: last?.resultSite,
    );
  }

  /// Pull-to-refresh: send what is waiting, then reload status and badge.
  Future<void> refresh() async {
    await _queue.flush();
    await Future.wait([refreshStatus(), refreshWaiting()]);
  }

  /// Checks (or asks for) location permission; the GPS stream runs only
  /// when it is granted.
  Future<LocationAccess> checkLocation({bool request = false}) async {
    final access = request ? await _location.request() : await _location.check();
    if (!mounted) return access;
    state = state.copyWith(locationAccess: access);
    if (access == LocationAccess.granted) {
      _tracker.start();
    } else {
      await _tracker.stop();
    }
    return access;
  }

  void setNfc(NfcAvailability availability) => state = state.copyWith(nfc: availability);
  void selectAction(PunchAction action) => state = state.copyWith(selectedAction: action);
  void cancelAction() => state = state.copyWith(selectedAction: null);
  void dismissResult() => state = state.copyWith(result: null);

  /// A card UID from reader mode, the iOS sheet or an Android launch intent.
  /// [takePhoto] opens the camera when the company requires a photo (§15).
  Future<TapOutcome> onCardRead(String uid, {Future<PunchPhoto?> Function()? takePhoto}) async {
    if (state.blocked || state.processing || state.result != null) {
      _taps.noteRead(uid);
      return const TapIgnored();
    }
    final outcome = await _taps.handle(
      uid,
      mode: state.punchMode,
      selected: state.selectedAction,
      photoRequired: state.photoRequired,
      takePhoto: takePhoto,
      onAccepted: () => state = state.copyWith(processing: true),
    );
    if (!mounted) return outcome;
    switch (outcome) {
      case TapIgnored() || TapNeedsAction() || TapNeedsLogin() || TapCancelled():
        state = state.copyWith(processing: false);
      case TapNoGps():
        state = state.copyWith(processing: false, result: outcome);
      case TapSent():
        state = state.copyWith(processing: false, result: outcome, selectedAction: null);
        unawaited(refreshStatus());
      case TapRejected():
        state = state.copyWith(processing: false, result: outcome, selectedAction: null);
        // The company may have changed its settings since the last /status (e.g. HR
        // switched photos on: `photo_required`). Re-read them so the next tap follows them
        // instead of being refused the same way again.
        unawaited(refreshStatus());
      case TapSaved():
        state = state.copyWith(processing: false, result: outcome, selectedAction: null);
    }
    return outcome;
  }

  void _onGps() {
    if (!mounted) return;
    final fix = _tracker.latest;
    final kind = _tracker.lastError != null
        ? GpsKind.error
        : !_tracker.isRunning
        ? GpsKind.off
        : (fix != null && _tracker.isFresh(fix))
        ? GpsKind.fix
        : GpsKind.searching;
    state = state.copyWith(gpsKind: kind, gpsAccuracy: fix?.accuracyM);
  }

  @override
  void dispose() {
    _storeChanges.cancel();
    _tracker.removeListener(_onGps);
    super.dispose();
  }
}

/// Company name, or the custom server's host.
String companyNameOf(Session session) =>
    session.company?.name ?? Uri.tryParse(session.serverUrl ?? '')?.host ?? '';
