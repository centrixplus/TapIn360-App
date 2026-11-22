import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android-only helpers implemented in MainActivity.kt on the
/// `nfc_attendance/system` channel.
class SystemChannel {
  SystemChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('nfc_attendance/system');

  final MethodChannel _channel;

  /// Opens the system NFC settings page (for the "Turn on NFC" banner).
  Future<void> openNfcSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openNfcSettings');
    } on PlatformException {
      // No settings activity on this device; the banner text still explains.
    }
  }

  /// Android: whether the camera permission is granted (Settings status).
  Future<bool?> cameraPermission() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<bool>('cameraPermission');
  }

  /// `Settings.Secure.ANDROID_ID` (spec §14): stable per device + signing key
  /// + user, survives reinstalls, changes on factory reset. Null off Android.
  Future<String?> androidId() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('getAndroidId');
  }
}
