import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_models.dart';

/// `device` block of `POST /login`: app-install ID, platform, model
/// (e.g. `SM-S928B`, `iPhone15,2`), `app_version` (`1.0.0+1`), the hardware ID
/// and the OS version (`16`, `18.1`) — spec §5.2 + §14.1.
Future<DeviceInfo> describeDevice(String deviceId, String hardwareId) async {
  var appVersion = '';
  var model = 'unknown';
  var osVersion = '';
  final platform = Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : Platform.operatingSystem);
  try {
    final package = await PackageInfo.fromPlatform();
    appVersion = '${package.version}+${package.buildNumber}';
    final plugin = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await plugin.androidInfo;
      model = info.model;
      osVersion = info.version.release;
    } else if (Platform.isIOS) {
      final info = await plugin.iosInfo;
      model = info.utsname.machine;
      osVersion = info.systemVersion;
    }
  } catch (error) {
    debugPrint('Device info unavailable: $error');
  }
  return DeviceInfo(
    id: deviceId,
    platform: platform,
    model: model,
    appVersion: appVersion,
    hardwareId: hardwareId,
    osVersion: osVersion,
  );
}

/// "1.0.0 (1)" for Settings.
Future<String> appVersionLabel() async {
  try {
    final package = await PackageInfo.fromPlatform();
    return '${package.version} (${package.buildNumber})';
  } catch (_) {
    return '';
  }
}
