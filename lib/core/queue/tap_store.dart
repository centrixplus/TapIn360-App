import 'tap_record.dart';

/// Local tap table: the offline queue and the History screen (spec §6.3).
abstract interface class TapStore {
  /// Fires after every change (badge and History refresh).
  Stream<void> get changes;

  Future<void> insert(TapRecord tap);
  Future<TapRecord?> byUuid(String clientUuid);

  /// The oldest waiting tap (insertion order), or null.
  Future<TapRecord?> oldestWaiting();
  Future<int> waitingCount();

  /// Newest first.
  Future<List<TapRecord>> recent({int limit = 50});

  /// [site] and [time] come from the `200` answer (History, Home "last tap").
  Future<void> markSent(
    String clientUuid, {
    required String result,
    required String message,
    String? site,
    DateTime? time,
  });

  /// The newest sent tap, or null.
  Future<TapRecord?> lastSent();
  Future<void> markRejected(String clientUuid, {required String code, required String message});

  /// Counts an attempt that got no usable answer, stores [error] and sets
  /// `offline: true` in the stored request for every later send. With
  /// [serverError] (the server answered, with an error) it also counts a
  /// server error and stores [at] as the first one if none is stored yet.
  Future<void> recordFailedAttempt(
    String clientUuid, {
    required String error,
    bool serverError = false,
    DateTime? at,
  });

  /// Deletes finished (sent/rejected) rows beyond the newest [keep].
  /// Waiting rows are never pruned.
  Future<void> prune({int keep = 50});

  /// Deletes every waiting row (logout confirmed). Returns how many.
  Future<int> discardWaiting();

  /// Rejects waiting taps of anyone but [employeeId] (code `discarded`), so a
  /// different employee logging in on this phone never sends them.
  Future<int> rejectWaitingNotOwnedBy(int employeeId, {required String message});

  Future<void> close();
}
