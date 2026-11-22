import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

import '../../core/api/api_models.dart';
import '../../core/location/location_gateway.dart';
import '../../core/tap/tap_outcome.dart';

enum StatusKind { loading, checkedIn, checkedOut, unavailable }

enum GpsKind { off, searching, fix, error }

/// Everything the Home screen shows (spec §6.1 item 3).
@immutable
class HomeState {
  const HomeState({
    required this.employeeName,
    required this.punchMode,
    required this.isIos,
    this.loggedIn = true,
    this.statusKind = StatusKind.loading,
    this.since,
    this.site,
    this.locationAccess,
    this.nfc,
    this.gpsKind = GpsKind.off,
    this.gpsAccuracy,
    this.waitingCount = 0,
    this.selectedAction,
    this.processing = false,
    this.result,
    this.photoRequired = false,
    this.companyName = '',
    this.lastTapAt,
    this.lastTapSite,
    this.accessSwitchedOff = false,
  });

  final String employeeName;
  final PunchMode punchMode;
  final bool isIos;
  final bool loggedIn;
  final StatusKind statusKind;
  final DateTime? since;
  final String? site;

  /// Null until checked.
  final LocationAccess? locationAccess;

  /// Android only; null until checked.
  final NfcAvailability? nfc;
  final GpsKind gpsKind;
  final double? gpsAccuracy;
  final int waitingCount;

  /// Manual mode: the button pressed before the tap.
  final PunchAction? selectedAction;
  final bool processing;

  /// Full-screen result being shown.
  final TapOutcome? result;

  /// Spec §15: each tap opens the camera.
  final bool photoRequired;

  /// Company name (TapIn360 directory) or the custom server's host.
  final String companyName;

  /// The newest tap this phone sent (status card "Last tap …").
  final DateTime? lastTapAt;
  final String? lastTapSite;

  /// `403 access_switched_off`: blocking banner, no taps, no camera.
  final bool accessSwitchedOff;

  /// First name for "Hello, …".
  String get firstName => employeeName.trim().split(RegExp(r'\s+')).first;

  bool get locationBlocked => locationAccess != null && locationAccess != LocationAccess.granted;
  bool get nfcBlocked => !isIos && nfc != null && nfc != NfcAvailability.enabled;

  /// A blocking banner is up: taps are not processed.
  bool get blocked => !loggedIn || accessSwitchedOff || locationBlocked || nfcBlocked;

  static const _unset = Object();

  HomeState copyWith({
    String? employeeName,
    PunchMode? punchMode,
    bool? loggedIn,
    StatusKind? statusKind,
    Object? since = _unset,
    Object? site = _unset,
    Object? locationAccess = _unset,
    Object? nfc = _unset,
    GpsKind? gpsKind,
    Object? gpsAccuracy = _unset,
    int? waitingCount,
    Object? selectedAction = _unset,
    bool? processing,
    Object? result = _unset,
    bool? photoRequired,
    String? companyName,
    Object? lastTapAt = _unset,
    Object? lastTapSite = _unset,
    bool? accessSwitchedOff,
  }) {
    return HomeState(
      employeeName: employeeName ?? this.employeeName,
      punchMode: punchMode ?? this.punchMode,
      isIos: isIos,
      loggedIn: loggedIn ?? this.loggedIn,
      statusKind: statusKind ?? this.statusKind,
      since: identical(since, _unset) ? this.since : since as DateTime?,
      site: identical(site, _unset) ? this.site : site as String?,
      locationAccess: identical(locationAccess, _unset)
          ? this.locationAccess
          : locationAccess as LocationAccess?,
      nfc: identical(nfc, _unset) ? this.nfc : nfc as NfcAvailability?,
      gpsKind: gpsKind ?? this.gpsKind,
      gpsAccuracy: identical(gpsAccuracy, _unset) ? this.gpsAccuracy : gpsAccuracy as double?,
      waitingCount: waitingCount ?? this.waitingCount,
      selectedAction: identical(selectedAction, _unset)
          ? this.selectedAction
          : selectedAction as PunchAction?,
      processing: processing ?? this.processing,
      result: identical(result, _unset) ? this.result : result as TapOutcome?,
      photoRequired: photoRequired ?? this.photoRequired,
      companyName: companyName ?? this.companyName,
      lastTapAt: identical(lastTapAt, _unset) ? this.lastTapAt : lastTapAt as DateTime?,
      lastTapSite: identical(lastTapSite, _unset) ? this.lastTapSite : lastTapSite as String?,
      accessSwitchedOff: accessSwitchedOff ?? this.accessSwitchedOff,
    );
  }
}
