import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/api/api_models.dart';
import 'package:nfc_attendance/core/tap/punch_action_resolver.dart';

void main() {
  test('auto mode always sends auto, whatever was selected', () {
    expect(resolvePunchAction(PunchMode.auto, null), PunchAction.auto);
    expect(resolvePunchAction(PunchMode.auto, PunchAction.checkIn), PunchAction.auto);
    expect(resolvePunchAction(PunchMode.auto, PunchAction.checkOut), PunchAction.auto);
  });

  test('manual mode sends the button the employee pressed', () {
    expect(resolvePunchAction(PunchMode.manual, PunchAction.checkIn), PunchAction.checkIn);
    expect(resolvePunchAction(PunchMode.manual, PunchAction.checkOut), PunchAction.checkOut);
  });

  test('manual mode without Check In / Check Out pressed → no punch', () {
    expect(resolvePunchAction(PunchMode.manual, null), isNull);
    expect(resolvePunchAction(PunchMode.manual, PunchAction.auto), isNull);
  });
}
