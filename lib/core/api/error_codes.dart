/// Error codes of API contract v1 (spec §5.3).
abstract final class ErrorCodes {
  static const badRequest = 'bad_request';
  static const invalidCredentials = 'invalid_credentials';
  static const invalidToken = 'invalid_token';

  /// Login or punch from a phone that is not the employee's approved phone (§14).
  static const deviceNotAllowed = 'device_not_allowed';

  /// The company's TapIn360 subscription is not active (TapIn360 spec §7). Final.
  static const subscriptionInactive = 'subscription_inactive';

  /// `403`: TapIn360 switched this employee's seat off (tapin_tenant `nfc_api.py`):
  /// on `/login` with the right PIN and on `/status`, `/punch`, `/logout` with the
  /// old token (revoked at that moment). Not final for queued taps: they wait.
  static const accessSwitchedOff = 'access_switched_off';
  static const locked = 'locked';
  static const unknownCard = 'unknown_card';
  static const locationRequired = 'location_required';
  static const mockLocation = 'mock_location';
  static const outOfRange = 'out_of_range';
  static const tooOld = 'too_old';
  static const invalidTime = 'invalid_time';
  static const olderThanLast = 'older_than_last';
  static const tooSoon = 'too_soon';
  static const alreadyCheckedIn = 'already_checked_in';
  static const notCheckedIn = 'not_checked_in';

  /// The server's own attendance rules refuse the record. Final.
  static const cannotRecord = 'cannot_record';

  /// Photo required by the company and missing (§15).
  static const photoRequired = 'photo_required';

  /// Not a decodable JPEG/PNG, or over 1 MB (§15).
  static const invalidPhoto = 'invalid_photo';

  static const all = {
    badRequest,
    invalidCredentials,
    invalidToken,
    deviceNotAllowed,
    subscriptionInactive,
    accessSwitchedOff,
    locked,
    unknownCard,
    locationRequired,
    mockLocation,
    outOfRange,
    tooOld,
    invalidTime,
    olderThanLast,
    tooSoon,
    alreadyCheckedIn,
    notCheckedIn,
    cannotRecord,
    photoRequired,
    invalidPhoto,
  };

  // App-side codes stored on rejected taps (never sent by a server).

  /// Waiting tap of another employee, closed when someone else logged in.
  static const discarded = 'discarded';

  /// The server kept answering with an error for this tap (see PunchQueue).
  static const undeliverable = 'undeliverable';
}
