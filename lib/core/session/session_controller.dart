import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_models.dart';
import '../api/api_outcome.dart';
import '../api/attendance_api.dart';
import '../directory/company.dart';
import '../queue/punch_queue.dart';
import '../queue/tap_store.dart';
import '../storage/session_store.dart';
import 'session.dart';

/// Login, logout, 401 expiry and server changes (spec §5.2, §6.1, §6.3).
class SessionController extends StateNotifier<Session> {
  SessionController({
    required Session initial,
    required this._storage,
    required this._api,
    required this._queue,
    required this._taps,
    required this._device,
  }) : super(initial);

  final SessionStore _storage;
  final AttendanceApi _api;
  final PunchQueue _queue;
  final TapStore _taps;
  final Future<DeviceInfo> Function() _device;

  /// Advanced → Custom server URL (no company).
  Future<void> saveServerUrl(String url) async {
    await _storage.saveServerUrl(url);
    await _storage.saveCompany(null);
    state = state.withServer(url);
  }

  /// Company found by code (TapIn360): its API base becomes the server URL.
  Future<void> chooseCompany(Company company) async {
    await _storage.saveServerUrl(company.apiBaseUrl);
    await _storage.saveCompany(company);
    state = state.withServer(company.apiBaseUrl, company: company);
  }

  /// Settings → Change company: logs out (caller confirmed discarding waiting
  /// taps) and returns to the company screen.
  Future<void> changeCompany() async {
    await logout();
    await _storage.clearServer();
    state = state.withoutServer();
  }

  Future<ApiOutcome<LoginResult>> login(String login, String password) async {
    final outcome = await _api.login(login: login, password: password, device: await _device());
    if (outcome case ApiOk(:final value)) {
      await _storage.saveLogin(
        token: value.token,
        employee: value.employee,
        punchMode: value.punchMode,
        photoRequired: value.photoRequired,
      );
      await _storage.saveSwitchedOff(false);
      // Waiting taps of someone else must never be sent with this token.
      await _taps.rejectWaitingNotOwnedBy(value.employee.id, message: '');
      state = state.withLogin(
        token: value.token,
        employee: value.employee,
        punchMode: value.punchMode,
        photoRequired: value.photoRequired,
      );
      _queue.resume();
      unawaited(_queue.flush());
    }
    return outcome;
  }

  /// `GET /status` answered: the company may have changed the punch mode.
  /// A seat that was switched off is on again: the block lifts and the
  /// waiting taps are sent.
  Future<void> applyStatus(StatusResult status) async {
    if (!state.isLoggedIn) return;
    final wasOff = state.accessSwitchedOff;
    state = state.withStatus(
      employee: status.employee,
      punchMode: status.punchMode,
      photoRequired: status.photoRequired,
    );
    await _storage.saveEmployee(
      employee: status.employee,
      punchMode: status.punchMode,
      photoRequired: status.photoRequired,
    );
    if (wasOff) {
      await _storage.saveSwitchedOff(false);
      if (!state.loggingOut) {
        _queue.resume();
        unawaited(_queue.flush());
      }
    }
  }

  /// `403 access_switched_off` on a tap or `/status`: TapIn360 switched this
  /// seat off. The queue pauses with every tap still Waiting, Home blocks taps
  /// (no camera) and shows why. TapIn360 also revokes the token, so once the
  /// seat is on again the server answers 401 and [expire] ends the session
  /// (the taps are sent after the next login); a `/status` that succeeds
  /// lifts the block directly.
  Future<void> switchOff() async {
    _queue.pause();
    if (!state.isLoggedIn || state.accessSwitchedOff) return;
    state = state.switchedOff();
    await _storage.saveSwitchedOff(true);
  }

  /// Any 401 on an authenticated call: the token is dead. The queue pauses
  /// (waiting taps are kept for the next login) and the router shows Login.
  Future<void> expire() async {
    _queue.pause();
    if (!state.isLoggedIn) return;
    state = state.loggedOut(expired: true);
    await _storage.clearLogin();
  }

  /// Logout after the user confirmed discarding waiting taps (§6.3).
  /// `POST /logout` is best effort; the local session ends either way. Taps
  /// are refused from the start ([Session.loggingOut]), so none is stored
  /// while the request runs and then lost with the waiting ones.
  Future<void> logout() async {
    _queue.pause();
    if (state.isLoggedIn) state = state.beginLogout();
    if (state.token != null) await _api.logout();
    await _taps.discardWaiting();
    await _storage.clearLogin();
    state = state.loggedOut(expired: false);
  }

  /// Settings → Server URL: changing it logs out (§6.1).
  Future<void> changeServer(String url) async {
    await logout();
    await saveServerUrl(url);
  }
}
