import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import 'gps_fix.dart';

/// [approximate]: permission is granted but only for the approximate location
/// (Android "Approximate", iOS "Precise: Off"): not enough to check the site
/// radius, so taps are blocked until precise location is allowed in Settings.
enum LocationAccess { granted, approximate, denied, deniedForever, serviceOff }

/// Thin wrapper over geolocator: permission, precision, service state, the
/// position stream and the system settings pages. The plugin calls can be
/// replaced in tests.
class LocationGateway {
  LocationGateway({
    Future<bool> Function()? serviceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<LocationAccuracyStatus> Function()? accuracy,
  }) : _serviceEnabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _accuracy = accuracy ?? Geolocator.getLocationAccuracy;

  final Future<bool> Function() _serviceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<LocationAccuracyStatus> Function() _accuracy;

  Future<LocationAccess> check() async {
    if (!await _serviceEnabled()) return LocationAccess.serviceOff;
    return _withPrecision(_map(await _checkPermission()));
  }

  /// Asks for "when in use" permission if it has not been refused for good.
  /// Approximate stays approximate: the banner opens Settings to change it.
  Future<LocationAccess> request() async {
    final current = await check();
    if (current != LocationAccess.denied) return current;
    return _withPrecision(_map(await _requestPermission()));
  }

  Stream<GpsFix> positions() {
    return Geolocator.getPositionStream(locationSettings: _settings()).map(
      (p) => GpsFix(
        lat: p.latitude,
        lng: p.longitude,
        accuracyM: p.accuracy,
        isMocked: p.isMocked,
        capturedAt: p.timestamp,
      ),
    );
  }

  Future<bool> openAppSettings() => Geolocator.openAppSettings();
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  /// Granted → [LocationAccess.approximate] when the platform says reduced.
  /// A platform that cannot tell (unknown, or the call fails) counts as precise.
  Future<LocationAccess> _withPrecision(LocationAccess access) async {
    if (access != LocationAccess.granted) return access;
    try {
      return await _accuracy() == LocationAccuracyStatus.reduced ? LocationAccess.approximate : access;
    } catch (_) {
      return access;
    }
  }

  static LocationAccess _map(LocationPermission permission) {
    return switch (permission) {
      LocationPermission.always || LocationPermission.whileInUse => LocationAccess.granted,
      LocationPermission.deniedForever => LocationAccess.deniedForever,
      _ => LocationAccess.denied,
    };
  }

  static LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 2),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high);
  }
}
