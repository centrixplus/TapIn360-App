import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/device/local_ip.dart';

class FakeInterface implements NetworkInterface {
  FakeInterface(this.name, List<String> ips) : addresses = ips.map(InternetAddress.new).toList();

  @override
  final String name;
  @override
  final List<InternetAddress> addresses;
  @override
  int get index => 0;
}

void main() {
  test('prefers Wi-Fi (wlan*) over mobile data', () {
    expect(
      pickLocalIpv4([
        FakeInterface('rmnet_data0', ['10.120.4.7']),
        FakeInterface('wlan0', ['192.168.1.25']),
      ]),
      '192.168.1.25',
    );
  });

  test('prefers en0 on iPhone', () {
    expect(
      pickLocalIpv4([
        FakeInterface('pdp_ip0', ['10.120.4.7']),
        FakeInterface('en0', ['192.168.1.30']),
      ]),
      '192.168.1.30',
    );
  });

  test('falls back to any IPv4 (mobile data)', () {
    expect(
      pickLocalIpv4([
        FakeInterface('rmnet_data0', ['10.120.4.7']),
      ]),
      '10.120.4.7',
    );
  });

  test('skips IPv6, loopback and link-local addresses', () {
    expect(
      pickLocalIpv4([
        FakeInterface('lo', ['127.0.0.1']),
        FakeInterface('wlan0', ['fe80::1', '169.254.3.4']),
        FakeInterface('rmnet_data0', ['2a02:1:2::5', '10.1.2.3']),
      ]),
      '10.1.2.3',
    );
  });

  test('no usable address → null', () {
    expect(pickLocalIpv4([]), isNull);
    expect(
      pickLocalIpv4([
        FakeInterface('lo', ['127.0.0.1']),
      ]),
      isNull,
    );
  });

  test('localIpv4 returns null when listing interfaces fails', () async {
    expect(await localIpv4(list: () async => throw const SocketException('denied')), isNull);
  });
}
