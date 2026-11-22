import '../api/api_models.dart';

/// The `action` to send: `auto` in auto mode; in manual mode the button the
/// employee pressed (Check In / Check Out), or null when none was pressed.
PunchAction? resolvePunchAction(PunchMode mode, PunchAction? selected) {
  return switch (mode) {
    PunchMode.auto => PunchAction.auto,
    PunchMode.manual => selected == PunchAction.auto ? null : selected,
  };
}
