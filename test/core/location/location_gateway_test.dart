import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nfc_attendance/core/location/location_gateway.dart';

void main() {
  late bool serviceOn;
  late LocationPermission permission;
  late LocationPermission afterRequest;
  late LocationAccuracyStatus accuracy;
  late Object? accuracyError;
  late int requests;
  late int accuracyCalls;
  late LocationGateway gateway;

  setUp(() {
    serviceOn = true;
    permission = LocationPermission.whileInUse;
    afterRequest = LocationPermission.whileInUse;
    accuracy = LocationAccuracyStatus.precise;
    accuracyError = null;
    requests = 0;
    accuracyCalls = 0;
    gateway = LocationGateway(
      serviceEnabled: () async => serviceOn,
      checkPermission: () async => permission,
      requestPermission: () async {
        requests++;
        permission = afterRequest;
        return afterRequest;
      },
      accuracy: () async {
        accuracyCalls++;
        if (accuracyError != null) throw accuracyError!;
        return accuracy;
      },
    );
  });

  test('precise "while in use" or "always" → granted', () async {
    expect(await gateway.check(), LocationAccess.granted);
    permission = LocationPermission.always;
    expect(await gateway.check(), LocationAccess.granted);
  });

  test('approximate only (Android "Approximate", iOS "Precise: Off") → approximate, not granted', () async {
    accuracy = LocationAccuracyStatus.reduced;
    expect(await gateway.check(), LocationAccess.approximate);
    permission = LocationPermission.always;
    expect(await gateway.check(), LocationAccess.approximate);
  });

  test('a platform that cannot tell the precision (unknown, or the call fails) counts as precise', () async {
    accuracy = LocationAccuracyStatus.unknown;
    expect(await gateway.check(), LocationAccess.granted);
    accuracyError = StateError('not supported');
    expect(await gateway.check(), LocationAccess.granted);
  });

  test('refused, refused for good and service off are reported before precision is asked', () async {
    permission = LocationPermission.denied;
    expect(await gateway.check(), LocationAccess.denied);
    permission = LocationPermission.deniedForever;
    expect(await gateway.check(), LocationAccess.deniedForever);
    serviceOn = false;
    expect(await gateway.check(), LocationAccess.serviceOff);
    expect(accuracyCalls, 0);
  });

  test('request: asks only when refused, and checks the precision of what the user allowed', () async {
    permission = LocationPermission.denied;
    afterRequest = LocationPermission.whileInUse;
    accuracy = LocationAccuracyStatus.reduced; // the user picked "Approximate" in the dialog
    expect(await gateway.request(), LocationAccess.approximate);
    expect(requests, 1);

    accuracy = LocationAccuracyStatus.precise;
    permission = LocationPermission.denied;
    expect(await gateway.request(), LocationAccess.granted);
    expect(requests, 2);
  });

  test('request with approximate already allowed does not ask again (Settings changes it)', () async {
    accuracy = LocationAccuracyStatus.reduced;
    expect(await gateway.request(), LocationAccess.approximate);
    expect(requests, 0);
  });
}
