import 'dart:io';

/// The phone's own IPv4 for `POST /punch` → `device.local_ip` (spec §14.1):
/// Wi-Fi first (`wlan*` on Android, `en0` on iPhone), else any other
/// interface (mobile data), else null. Loopback and link-local are skipped.
String? pickLocalIpv4(List<NetworkInterface> interfaces) {
  String? firstUsable(Iterable<NetworkInterface> candidates) {
    for (final interface in candidates) {
      for (final address in interface.addresses) {
        if (address.type == InternetAddressType.IPv4 && !address.isLoopback && !address.isLinkLocal) {
          return address.address;
        }
      }
    }
    return null;
  }

  final wifi = interfaces.where((i) => i.name.startsWith('wlan') || i.name == 'en0');
  return firstUsable(wifi) ?? firstUsable(interfaces);
}

/// Reads the interfaces now (captured at tap time). Null on any error.
Future<String?> localIpv4({Future<List<NetworkInterface>> Function()? list}) async {
  try {
    final interfaces = await (list ?? () => NetworkInterface.list(type: InternetAddressType.IPv4))();
    return pickLocalIpv4(interfaces);
  } catch (_) {
    return null;
  }
}
