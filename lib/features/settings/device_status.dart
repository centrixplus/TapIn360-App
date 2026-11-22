import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

import '../../app/providers.dart';
import '../../core/location/location_gateway.dart';

/// Permission / hardware status shown in Settings.
class DeviceStatus {
  const DeviceStatus({this.location, this.camera, this.nfc});

  final LocationAccess? location;

  /// Null when the platform cannot tell without asking (iOS).
  final bool? camera;
  final NfcAvailability? nfc;
}

final deviceStatusProvider = FutureProvider.autoDispose<DeviceStatus>((ref) async {
  LocationAccess? location;
  NfcAvailability? nfc;
  bool? camera;
  try {
    location = await ref.read(locationGatewayProvider).check();
  } catch (_) {}
  try {
    nfc = await ref.read(nfcReaderProvider).availability();
  } catch (_) {}
  if (Platform.isAndroid) {
    try {
      camera = await ref.read(systemChannelProvider).cameraPermission();
    } catch (_) {}
  }
  return DeviceStatus(location: location, camera: camera, nfc: nfc);
});
