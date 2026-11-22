import 'package:flutter/foundation.dart';

import '../api/api_models.dart';
import '../directory/company.dart';

/// Who is logged in, against which server (spec §5, §6.1), plus the company
/// settings cached from `/login` and `/status`.
@immutable
class Session {
  const Session({
    required this.deviceId,
    this.serverUrl,
    this.token,
    this.employee,
    this.punchMode = PunchMode.auto,
    this.photoRequired = false,
    this.expired = false,
    this.company,
    this.accessSwitchedOff = false,
    this.loggingOut = false,
  });

  /// App-install UUID sent as `device.id` on login.
  final String deviceId;
  final String? serverUrl;
  final String? token;
  final Employee? employee;
  final PunchMode punchMode;

  /// `settings.photo_required` (spec §15): open the camera on every tap.
  final bool photoRequired;

  /// The last session ended with a 401 (token revoked), not a logout.
  final bool expired;

  /// Company picked by code (TapIn360); null with a custom server URL.
  final Company? company;

  /// The server answered `403 access_switched_off` (TapIn360 switched the
  /// seat off): taps are blocked and the queue is paused until a `/status`
  /// succeeds again or the session ends.
  final bool accessSwitchedOff;

  /// Logout started: taps are refused while `POST /logout` runs, so none is
  /// stored and then discarded with the waiting taps.
  final bool loggingOut;

  bool get hasServer => serverUrl != null;
  bool get isLoggedIn => token != null && employee != null;

  /// Logged in and not switched off or logging out: a tap may be taken.
  bool get canTap => isLoggedIn && !accessSwitchedOff && !loggingOut;

  Session withServer(String url, {Company? company}) =>
      Session(deviceId: deviceId, serverUrl: url, company: company);

  /// Change company: back to the company screen.
  Session withoutServer() => Session(deviceId: deviceId);

  Session withLogin({
    required String token,
    required Employee employee,
    required PunchMode punchMode,
    required bool photoRequired,
  }) {
    return Session(
      deviceId: deviceId,
      serverUrl: serverUrl,
      token: token,
      employee: employee,
      punchMode: punchMode,
      photoRequired: photoRequired,
      company: company,
    );
  }

  /// A successful `/status` (also lifts [accessSwitchedOff]).
  Session withStatus({
    required Employee employee,
    required PunchMode punchMode,
    required bool photoRequired,
  }) {
    return Session(
      deviceId: deviceId,
      serverUrl: serverUrl,
      token: token,
      employee: employee,
      punchMode: punchMode,
      photoRequired: photoRequired,
      company: company,
      loggingOut: loggingOut,
    );
  }

  Session switchedOff() => _copy(accessSwitchedOff: true);

  Session beginLogout() => _copy(loggingOut: true);

  Session loggedOut({required bool expired}) {
    return Session(
      deviceId: deviceId,
      serverUrl: serverUrl,
      punchMode: punchMode,
      photoRequired: photoRequired,
      expired: expired,
      company: company,
    );
  }

  Session _copy({bool? accessSwitchedOff, bool? loggingOut}) {
    return Session(
      deviceId: deviceId,
      serverUrl: serverUrl,
      token: token,
      employee: employee,
      punchMode: punchMode,
      photoRequired: photoRequired,
      expired: expired,
      company: company,
      accessSwitchedOff: accessSwitchedOff ?? this.accessSwitchedOff,
      loggingOut: loggingOut ?? this.loggingOut,
    );
  }
}
