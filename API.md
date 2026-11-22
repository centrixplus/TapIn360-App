# NFC Attendance — Server API v1

This is the contract between the **NFC Attendance** mobile app (Android + iPhone) and any attendance
server. Odoo 20 (`nfc_attendance` module) is the first implementation; any system that implements the
four endpoints below works with the same app, unchanged.

Source of truth: `docs/superpowers/specs/2026-11-17-nfc-attendance-design.md` §5. This document adds
examples and describes exactly how the app reacts to each answer, so you can implement a server
without reading the app's code.

---

## 1. How the app uses the API

1. An employee installs the app, enters the **Server URL** (the base URL below) and logs in with an
   ID and a password/PIN.
2. A card is fixed on the wall at each work site. The card identifies the **site**; the logged-in
   phone identifies the **person**.
3. On each tap the app reads the card's chip UID, takes a GPS fix and sends `POST /punch`.
4. The server decides check-in / check-out (or rejects), and returns a message the app shows on a
   full-screen green ✓ or red ✗.
5. If the server cannot be reached, the tap is kept on the phone and sent later (oldest first).

---

## 2. General rules

| Rule | Detail |
|---|---|
| Base URL | Configured in the app, e.g. `https://erp.client.com/nfc/api/v1`. The app strips trailing slashes and appends `/login`, `/punch`, `/status`, `/logout`. |
| Format | Plain JSON request and response bodies, `Content-Type: application/json`. **Not** JSON-RPC (no `jsonrpc`/`params`/`result` envelope). |
| Auth | `/punch`, `/status`, `/logout` send `Authorization: Bearer <token>`. `/login` does not. |
| Language | Every request has `Accept-Language: en` or `Accept-Language: ar`. Return `message` texts in that language. The app shows them verbatim. |
| Server timestamps | ISO 8601 **UTC** with `Z`: `2026-11-17T06:02:11Z`. |
| App timestamps | ISO 8601 with the phone's UTC offset, whole seconds: `2026-11-17T09:02:11+03:00`. |
| Errors | Always `{"error": {"code": "<code>", "message": "<text for the employee>"}}`. Extra fields may be added **inside** `error` (e.g. `distance_m`, `retry_after_s`). |
| Transport | HTTPS. The app refuses plain `http://` except for `localhost`, `127.0.0.1` and `10.0.2.2` (local testing over `adb reverse` / the Android emulator); on-premise servers need HTTPS too. |
| Database | The app sends no database/tenant name; the server must resolve the right database from the URL/host. |

### Headers the app sends

```
Accept: application/json
Accept-Language: en            (or ar)
Content-Type: application/json (requests with a body)
Authorization: Bearer <token>  (all except /login)
```

---

## 3. Endpoints

### 3.1 `POST /login`

Request:

```json
{
  "login": "041234567890",
  "password": "1234",
  "device": {
    "id": "3f0b6a52-6c1e-4d0b-9a59-2f3e8f1d7c44",
    "platform": "android",
    "model": "SM-S928B",
    "app_version": "1.0.0+1",
    "hardware_id": "a1b2c3d4e5f60718",
    "os_version": "16"
  }
}
```

| Field | Meaning |
|---|---|
| `login` | The employee's ID as typed (Odoo: **Badge ID**). Leading/trailing spaces are trimmed by the app. |
| `password` | Password or PIN as typed. |
| `device.id` | UUID generated once per app install. Stable across logins on the same install. |
| `device.platform` | `android` or `ios`. |
| `device.model` | Android model (`SM-S928B`) or iOS machine id (`iPhone15,2`). |
| `device.app_version` | `version+build`, e.g. `1.0.0+1`. |
| `device.hardware_id` | **Required** (missing → `400 bad_request`). The phone's hardware ID: Android `Settings.Secure.ANDROID_ID`, iOS `identifierForVendor`. Survives app reinstalls. See §9 (device binding) and why it is not the IMEI. |
| `device.os_version` | OS version, e.g. `16` (Android) or `18.1` (iOS). |

Response `200`:

```json
{
  "token": "pR3x0…opaque…",
  "employee": { "id": 17, "name": "Ahmed Ali" },
  "settings": { "punch_mode": "auto", "photo_required": true },
  "server_time": "2026-11-17T06:00:00Z"
}
```

| Field | Rules |
|---|---|
| `token` | Opaque, non-empty string. The app stores it in secure storage. |
| `employee.id` | Integer. The app tags queued taps with it (see §5.4). |
| `employee.name` | Shown on Home. |
| `settings.punch_mode` | `auto` (server toggles in/out) or `manual` (employee presses Check In / Check Out first). Anything else is treated as `auto`. |
| `settings.photo_required` | `true` → the app takes a front-camera photo on every tap and sends it in `/punch` (§10). `false` or absent → no camera. Cached on the phone with the other settings. |
| `server_time` | Informational. |

Rules:
- Logging in again from the same `device.id` **replaces** that device's previous token.
- Tokens do not expire in v1; they end on `POST /logout` or when an administrator revokes them.

Errors: `401 invalid_credentials`, `423 locked` (with `retry_after_s`), `403 device_not_allowed`
(right PIN, but not the employee's approved phone — §9; no token is issued), `400 bad_request`.
On `403` the app stays on Login, shows your `message` and shows **This phone's ID** (the
`hardware_id`) so the employee can give it to HR.

```json
HTTP/1.1 423 Locked
{ "error": { "code": "locked",
             "message": "Too many wrong PINs. Try again in 15 minutes.",
             "retry_after_s": 900 } }
```

### 3.2 `POST /punch` (Bearer)

Request:

```json
{
  "client_uuid": "6f1c2a9e-8d4b-4c47-9b1e-0f6a2b7d9c31",
  "card_uid": "04DB8FE23B1590",
  "action": "auto",
  "tapped_at": "2026-11-17T09:02:11+03:00",
  "offline": false,
  "location": {
    "lat": 29.3759,
    "lng": 47.9774,
    "accuracy_m": 8.5,
    "is_mocked": false,
    "captured_at": "2026-11-17T09:02:09+03:00"
  },
  "device": {
    "hardware_id": "a1b2c3d4e5f60718",
    "local_ip": "192.168.1.25"
  },
  "photo": {
    "mime": "image/jpeg",
    "data": "/9j/4AAQSkZJRgABAQAAAQABAAD…",
    "taken_at": "2026-11-17T09:02:14+03:00",
    "faces": 1
  }
}
```

| Field | Rules |
|---|---|
| `client_uuid` | UUID v4 created by the app for this tap. **Idempotency key** (§4). Resends of the same tap reuse it. |
| `card_uid` | Chip UID, uppercase hex, no separators (`04:db:8f:e2:3b:15:90` → `04DB8FE23B1590`). NTAG213 cards have 7-byte UIDs (14 hex chars); other cards can have 4 or 10 bytes. Normalise registered UIDs the same way before comparing. |
| `action` | `auto` \| `check_in` \| `check_out`. **The request's `action` decides, whatever the company's current punch mode**: `auto` toggles (open attendance → check-out, else check-in); an explicit `check_in` / `check_out` is validated (`already_checked_in` / `not_checked_in`). The app sends `auto` in auto mode and the employee's choice in manual mode; a queued tap keeps the action it was created with, so it stays valid if the mode changes before it is sent. |
| `tapped_at` | Phone clock at the moment the card was read, with offset. |
| `offline` | `false` when the tap is sent at tap time. `true` when it is sent from the queue: either the server did not answer at tap time, or older taps were already waiting so the new tap was queued behind them (§5.1). |
| `location.lat` / `lng` | WGS84 decimal degrees. |
| `location.accuracy_m` | Horizontal accuracy in metres (float). Indoors typically 15–35 m. |
| `location.is_mocked` | Android: the OS "mock location" flag. iOS: reported when the platform knows it, otherwise `false`. |
| `location.captured_at` | When the fix was taken (with offset). Up to 30 s before `tapped_at`, or up to 10 s after it. |
| `device.hardware_id` | Same value as on `/login`. Must match the device the token was issued to, else `403 device_not_allowed`. |
| `photo` | Present when `settings.photo_required` is on (§10). `mime` is `image/jpeg`; `data` is the **standard base64** of the JPEG (no `data:` prefix), at most 640 px on the long side, quality ≈ 70, typically 40–90 KB; `taken_at` is when the photo was taken (with offset; a few seconds after `tapped_at`); `faces` is the number of faces the phone found (always `1` — the app refuses other photos). The same photo is resent with a queued tap. |
| `device.local_ip` | The phone's own IPv4 at tap time: Wi-Fi first (`wlan*` / `en0`), else mobile data, else `null`. Private addresses are normal (e.g. `192.168.1.25`, `10.x`). Captured at tap time and stored with a queued tap, so a resend keeps the tap-time value. Informational only — record the **public** IP you see yourself (§9.3). |

The app **never** sends a punch without a location (no GPS fix in 10 s → nothing is sent or
stored). `location_required` exists for other clients.

Response `200`:

```json
{
  "result": "check_in",
  "time": "2026-11-17T06:02:11Z",
  "site": "Head Office",
  "message": "Checked in at 09:02 — Head Office"
}
```

| Field | Rules |
|---|---|
| `result` | `check_in` or `check_out` — the app uses it for the title ("Checked in" / "Checked out"). |
| `time` | Attendance time recorded (UTC). |
| `site` | Site name of the card. |
| `message` | Shown under the title, verbatim. |

Any `200` means "recorded". The app marks the tap **Sent** and refreshes `/status`.

### 3.3 `GET /status` (Bearer)

Response `200`:

```json
{
  "employee": { "id": 17, "name": "Ahmed Ali" },
  "state": "checked_in",
  "since": "2026-11-17T05:02:00Z",
  "site": "Head Office",
  "punch_mode": "auto",
  "settings": { "photo_required": true },
  "server_time": "2026-11-17T08:00:00Z"
}
```

Checked out:

```json
{
  "employee": { "id": 17, "name": "Ahmed Ali" },
  "state": "checked_out",
  "since": null,
  "site": null,
  "punch_mode": "auto",
  "server_time": "2026-11-17T08:00:00Z"
}
```

- `state`: `checked_in` | `checked_out`. `since` and `site` are `null` when checked out.
- The app shows "Checked in since 08:02 — Head Office" (local time) or "Checked out", and takes
  `punch_mode`, `settings.photo_required` and the employee name from here, so a company setting
  change reaches phones on the next refresh. (The app also accepts a top-level `photo_required`.)
- **Without a token** this endpoint must answer `401` with code `invalid_token` in the standard
  error shape. The app's Server setup **Test** button sends `GET /status` with no `Authorization`
  header and accepts the server only if it gets exactly that:

```json
HTTP/1.1 401 Unauthorized
{ "error": { "code": "invalid_token", "message": "Please log in." } }
```

### 3.4 `POST /logout` (Bearer)

The app sends an empty JSON object `{}` as the body. Response `200`:

```json
{ "ok": true }
```

The token is revoked. The app ends the local session even if this call fails.

---

## 4. Idempotency and time

- Store `client_uuid` for **every** punch request, including rejected ones, together with the
  response you returned (HTTP status + body).
- A request with an already-stored `client_uuid` must return the **original** response — same status,
  same body — and create nothing. (Typical case: the first send reached you but the answer was lost;
  the app resends with `offline: true`.)
- **Online** (`offline: false`): the attendance time is the **server's** clock.
- **Offline** (`offline: true`): the attendance time is `tapped_at`; flag the record as offline.

---

## 5. How the app reacts to each answer

| Server answer | App behaviour |
|---|---|
| `2xx` + JSON object | Success. Punch → **Sent**, green result. |
| `4xx` in the standard error shape | **Rejected**, red result with `error.message`. Never retried. |
| `4xx` without the standard shape | Treated as **no answer** (not your API — e.g. a proxy 404): the tap stays Waiting and is resent. Always use the standard shape for real rejections. |
| `401` on `/punch`, `/status`, `/logout` | The token is dead: the app logs out locally and shows Login, and the queue pauses. A tap sent at tap time (`offline: false`) is Rejected; queued taps (`offline: true`) stay Waiting and are sent after the next login (§5.4). |
| `5xx`, timeout (10 s), connection error | Punch stays **Waiting**, the employee sees "Saved — will send automatically"; it is resent later with `offline: true` and the same `client_uuid`. |
| `3xx` | Redirects are not followed; treated like no answer. The Test button reports the redirect target. |
| `2xx` whose body is not a JSON object | Treated like no answer (resent; your idempotent replay answers it). |
| `200` on `/login` without `token` or `employee` | Treated as a broken server ("cannot reach"). |

### 5.1 Retry schedule

Waiting taps are sent **strictly oldest first, one at a time**, while the app is open: at app start
and resume, when connectivity returns, every 60 s, and after each new tap. The first tap that gets
no answer stops the round.

A new tap is sent immediately (`offline: false`) **only when nothing is waiting**. If older taps are
waiting, the new tap is stored behind them with `offline: true` (so its attendance time is its
`tapped_at`), the employee sees "Saved — will send automatically", and the queue is flushed
oldest-first. You therefore never receive a younger tap before an older one from the same phone,
and older taps are not rejected as `older_than_last` because of a newer one.

### 5.2 What is never sent

- Reads of the same card within 10 s of the previous read (holding the card is one tap).
- Taps without a GPS fix within 10 s.
- Taps while location permission or NFC is off.

### 5.3 Rejections the app cannot fix by retrying

Every `4xx` is final for that tap, including `cannot_record` (your attendance rules refuse the
record). Make sure transient server problems answer `5xx`, not `4xx`.

### 5.4 Waiting taps and a different employee

Waiting taps belong to the employee who was logged in at tap time. If a *different* employee logs
in on the same phone, those taps are closed locally as not sent and are never sent with the new
token. Logging out with waiting taps asks "Discard N unsent taps?" and deletes them on confirm.

### 5.5 `403 device_not_allowed`

- On `/login`: the app stays on Login, shows your `message` and this phone's ID.
- On `/punch`: a final rejection like any `4xx` (red result with your `message`, never retried).
  It does **not** log the employee out — only `401` does.

### 5.6 Photo taps

- With `photo_required` on, the camera opens after the card read; the punch is stored and sent only
  once a photo with exactly one face is taken. If the employee presses **Cancel**, nothing is stored
  or sent — you never receive that tap.
- `photo_required` and `invalid_photo` are final rejections like any `4xx`.

---

## 6. Error codes

| HTTP | `code` | When | Extra fields |
|---|---|---|---|
| 400 | `bad_request` | Malformed JSON or missing fields | |
| 401 | `invalid_credentials` | Login: wrong ID or PIN | |
| 401 | `invalid_token` | Missing, unknown or revoked token (also: the token's device was replaced by a newly approved phone) | |
| 403 | `device_not_allowed` | Login or punch from a phone that is not the employee's approved phone (§9) | |
| 403 | `subscription_inactive` | The company's TapIn360 subscription is not active (TapIn360 platform). Final; on Login the app shows the message and stays | |
| 403 | `access_switched_off` | TapIn360 switched the employee's seat off: `/login` with the right PIN, and `/status`, `/punch`, `/logout` with the old (revoked) token. Not final for taps: the app keeps them Waiting, pauses the queue and blocks taps until a `/status` succeeds or the session ends | |
| 422 | `photo_required` | `photo_required` is on and the request has no `photo` (§10) | |
| 422 | `invalid_photo` | `photo.data` is not a decodable JPEG/PNG, or is over 1 MB decoded (§10) | |
| 423 | `locked` | Too many wrong PINs | `retry_after_s` |
| 422 | `unknown_card` | Card not registered, inactive, or another company's | |
| 422 | `site_not_ready` | The card is registered but its site has no GPS point yet (TapIn360 registers cards before HR sets the point). Final; the app shows `message` | |
| 422 | `location_required` | No location in the request | |
| 422 | `mock_location` | `is_mocked` is true | |
| 422 | `out_of_range` | Outside the site radius | `distance_m` (Odoo: integer metres) |
| 422 | `too_old` | Offline tap older than the company limit | |
| 422 | `invalid_time` | Tap time more than 5 minutes in the future | |
| 422 | `older_than_last` | Tap time earlier than the employee's latest attendance event | |
| 422 | `too_soon` | Within the minimum gap after the last attendance event | optional `retry_after_s` (Odoo sends it) |
| 422 | `already_checked_in` | Manual `check_in` while checked in (or a single-check-in rule blocks the check-out) | |
| 422 | `not_checked_in` | Manual `check_out` while checked out | |
| 422 | `cannot_record` | The server's own attendance rules refuse the record (e.g. HR edited attendances so the close would overlap). Final — retrying cannot help. | |
| 5xx | (any) | Server fault — the app queues and retries | |

Example:

```json
HTTP/1.1 422 Unprocessable Entity
{ "error": { "code": "out_of_range",
             "message": "You are 140 m from Head Office.",
             "distance_m": 140 } }
```

### 6.1 Reference check order for `/punch` (Odoo implementation)

Not part of the wire contract, but recommended so all servers behave alike (first failure wins):

1. Token missing/unknown/revoked → `401 invalid_token`.
   Device binding on (§9): the token's device is no longer approved → `401 invalid_token`;
   request `device.hardware_id` differs from the token's device → `403 device_not_allowed`.
2. `client_uuid` already stored (from the same token) → replay the stored response.
3. Photo (§10), before anything else is evaluated: `photo_required` on and no `photo` →
   `photo_required`; `photo` not a decodable JPEG/PNG or over 1 MB decoded → `invalid_photo`.
4. Card UID not an active card of the employee's company → `unknown_card`; the card has no GPS
   point yet (latitude and longitude both 0) → `site_not_ready`.
5. No location → `location_required`; `is_mocked` → `mock_location`.
6. Haversine distance from the card's point; reject `out_of_range` when
   `distance_m > radius_m + min(accuracy_m, 50)`.
7. Event time = server now (online) or `tapped_at` (offline): offline and older than the company
   limit → `too_old`; more than 5 min in the future → `invalid_time`; earlier than the employee's
   latest check-in/check-out → `older_than_last`.
8. Event time within the minimum gap of the latest event → `too_soon` (the message names the
   previous event, e.g. "Already checked in at 08:02").
9. Action (from the request, not the company mode) — `auto`: open attendance → check-out, else
   check-in. `check_in` while checked in → `already_checked_in`; `check_out` while checked out →
   `not_checked_in`.
10. Record the attendance; if your attendance rules refuse it → `cannot_record`. Log the punch
    with its response, return `200`.

Log every outcome, including rejections, and store the response for idempotent replay.

---

## 7. Try it with curl

```bash
BASE=http://localhost:8046/nfc/api/v1

# Server setup "Test": must be 401 invalid_token
curl -i "$BASE/status"

# Login
curl -s -X POST "$BASE/login" -H 'Content-Type: application/json' -H 'Accept-Language: en' \
  -d '{"login":"041234567890","password":"1234",
       "device":{"id":"3f0b6a52-6c1e-4d0b-9a59-2f3e8f1d7c44","platform":"android",
                 "model":"SM-S928B","app_version":"1.0.0+1",
                 "hardware_id":"a1b2c3d4e5f60718","os_version":"16"}}'

TOKEN=...   # from the login response

# Punch (send the same body twice: the second answer must be identical)
curl -s -X POST "$BASE/punch" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -H 'Accept-Language: ar' \
  -d '{"client_uuid":"6f1c2a9e-8d4b-4c47-9b1e-0f6a2b7d9c31","card_uid":"04DB8FE23B1590",
       "action":"auto","tapped_at":"2026-11-17T09:02:11+03:00","offline":false,
       "location":{"lat":29.3759,"lng":47.9774,"accuracy_m":8.5,"is_mocked":false,
                   "captured_at":"2026-11-17T09:02:09+03:00"},
       "device":{"hardware_id":"a1b2c3d4e5f60718","local_ip":"192.168.1.25"}}'

curl -s "$BASE/status" -H "Authorization: Bearer $TOKEN"
curl -s -X POST "$BASE/logout" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{}'
```

## 8. Conformance checklist

- [ ] All four paths under one base URL; JSON in and out; no JSON-RPC envelope.
- [ ] `GET /status` without a token → `401` + `{"error":{"code":"invalid_token",…}}`.
- [ ] Login returns `token`, `employee{id,name}`, `settings.punch_mode`; same `device.id` replaces its old token.
- [ ] Every error uses the standard shape; transient faults are `5xx`, never `4xx`.
- [ ] `client_uuid` replay returns the original status and body, including for rejections.
- [ ] Online punches use server time; offline punches use `tapped_at` and are flagged.
- [ ] `message` texts follow `Accept-Language` (`en`, `ar`).
- [ ] Server timestamps are UTC with `Z`.
- [ ] `/login` requires `device.hardware_id`; device binding answers `403 device_not_allowed` (§9).
- [ ] The public client IP is recorded for every request (behind a proxy: trust `X-Forwarded-For`).
- [ ] `settings.photo_required` on `/login` and `/status`; `photo_required` / `invalid_photo` enforced; photos up to 1 MB decoded accepted.

## 9. Device binding and IP address (Amendment 1)

### 9.1 Why a hardware ID and not the IMEI

Since Android 10, reading the IMEI or serial number needs `READ_PRIVILEGED_PHONE_STATE`, which only
system, carrier-privileged or device-owner (MDM) apps can hold; iOS has no IMEI API at all. The app
therefore sends a **hardware ID** that survives app reinstalls:

| Platform | `hardware_id` | Changes when |
|---|---|---|
| Android | `Settings.Secure.ANDROID_ID` (64-bit hex) | factory reset, a different app signing key, or another user profile |
| iOS | `identifierForVendor` (UUID), cached in the Keychain-backed secure storage | all apps of the vendor are removed and the cache is lost |

If the platform returns nothing (rare; iOS before the first unlock), the app uses its app-install
ID instead and keeps it from then on. Company-owned MDM phones with real IMEI access are out of
scope.

### 9.2 Binding rules (reference: Odoo)

A company setting turns binding on (default) or off; when off, devices are still recorded but
never block.

- **Login** (after the PIN is correct):
  - employee has no approved device → this phone becomes the approved device;
  - `hardware_id` matches the approved device → OK (update last seen, model, OS);
  - otherwise → record the phone as **pending**, issue no token, answer `403 device_not_allowed`.
    The failed-PIN counter is not touched (the PIN was right).
- **Approve** (HR, on a pending device): it becomes the employee's single approved device; the
  previous approved device is removed and **all its tokens are revoked** (that phone gets `401`
  and goes back to Login).
- **Punch**, right after the token check: token's device no longer approved → `401 invalid_token`;
  `device.hardware_id` differs from the token's device → `403 device_not_allowed`.

Message for `device_not_allowed`: "This phone is not registered for you. Ask HR to approve it."
The employee can read **This phone's ID** on the Login screen (after the `403`) and in Settings, so
HR can match it with the pending device.

### 9.3 IP addresses

- `device.local_ip` (from the app) is the phone's private address; useful to see which Wi-Fi the
  phone was on, not proof of anything.
- Record the **public** IP you see for every request yourself — the app cannot fake it. Behind a
  reverse proxy use the forwarded address (Odoo: `proxy_mode = True`, so `X-Forwarded-For` is used).

## 10. Employee photo on every tap (Amendment 2)

- **Setting:** `settings.photo_required` on `/login` and `/status` (Odoo: company setting, default on).
  The app opens the camera only when it is `true`, so a server that does not want photos sends
  `false` (or nothing).
- **On the phone:** after the card read the in-app **front camera** opens full screen (no gallery):
  3-second countdown with automatic capture, plus a shutter button. Google ML Kit counts faces on the
  phone, offline: exactly **one** face is required ("Face not visible — try again" / "Only you should
  be in the photo"), the employee can retry, and **Cancel** discards the tap. The GPS fix is taken
  while the camera is open; `tapped_at` stays the moment the card was read.
- **Photo sent:** JPEG, EXIF rotation applied, at most **640 px** on the long side, quality ≈ 70
  (lowered automatically if ever needed to stay under 1,000,000 bytes); typically 40–90 KB.
  Base64 in `photo.data` (≈ 55–120 KB of JSON).
- **Server limit:** reject anything over **1 MB decoded** or not a decodable JPEG/PNG with
  `422 invalid_photo`; a missing photo while required is `422 photo_required`. Both are final.
- **Faces:** the server cannot verify faces; record `photo.faces` as reported.
- **Offline:** the photo is stored inside the queued punch (same `client_uuid`) and sent with it.
  After a tap is sent or rejected the phone keeps only the photo metadata, not the image.
- **Order of checks:** the photo checks run after the token/device checks and before the card check
  (§6.1), so a tap without a required photo is rejected before anything else is evaluated.

## 11. TapIn360 platform (company directory)

The TapIn360 app does not ask employees for a server URL. It opens on **Your company**: the code is
typed or scanned from a QR (`tapin://company/<code>`), then the app calls the TapIn360 master
directory (not part of this attendance API):

```
GET https://account.tapin360.co/tapin/api/v1/company/<code>
200 {"code": "acme", "name": "Acme Trading Co.", "logo_url": null,
     "api_base_url": "https://acme.tapin360.co/nfc/api/v1", "status": "active"}
404 {"error": {"code": "not_found", "message": "Not found."}}
```

- `api_base_url` is the base URL of this API for that company; the app uses it exactly like a
  typed Server URL.
- `status`: `active` and `grace` can log in; `provisioning` and `suspended` cannot (the app says
  why). Deleted companies answer 404.
- Other platforms that are not on TapIn360 keep working through **Use a custom server**.
- `403 subscription_inactive` (§6) is final on `/login` and `/punch`.
