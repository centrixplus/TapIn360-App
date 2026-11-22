/// Spec §6.2 step 2: the same UID within [window] of the previous read is
/// ignored. Every read counts as "the previous read", including ignored ones,
/// so holding the card on the phone (Android re-reads it about every second)
/// stays a single tap.
class TapDebouncer {
  TapDebouncer({this.window = const Duration(seconds: 10)});

  final Duration window;
  String? _lastUid;
  DateTime? _lastAt;

  /// Records the read and says whether it is a new tap.
  bool accept(String uid, DateTime at) {
    final lastAt = _lastAt;
    final duplicate = uid == _lastUid && lastAt != null && at.difference(lastAt) < window;
    _lastUid = uid;
    _lastAt = at;
    return !duplicate;
  }

  void reset() {
    _lastUid = null;
    _lastAt = null;
  }
}
