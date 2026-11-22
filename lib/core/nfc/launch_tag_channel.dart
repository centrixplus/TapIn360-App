import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// UID of the wall card that launched (app closed) or resumed (app in
/// background) the app on Android. iOS never delivers launch tags.
class LaunchTagChannel {
  LaunchTagChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('nfc_attendance/launch_tag');

  final MethodChannel _channel;

  /// The UID that cold-started the app, once; null afterwards or on iOS.
  Future<String?> takeLaunchTag() async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('takeLaunchTag');
  }

  /// Called for each tap that arrives while the app is in the background.
  void listen(void Function(String uid) onUid) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'launchTag' && call.arguments is String) {
        onUid(call.arguments as String);
      }
    });
  }
}
