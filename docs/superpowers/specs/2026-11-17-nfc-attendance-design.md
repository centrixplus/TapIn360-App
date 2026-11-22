# NFC Attendance — Design (Phase 1)

- **Date:** 2026-11-17
- **Status:** Design approved in brainstorming; spec awaiting review
- **Parts:** Flutter app (Android + iPhone) · Odoo 20 module `nfc_attendance` · `API.md` contract

## 1. Goal

An employee opens the app on their own phone and taps an NFC card fixed on the wall at a work site.
The app sends the card's ID, the phone's GPS location and the tap time to a configurable server API.
The server records a check-in or check-out, or rejects the tap with a reason the app shows.

The API is platform-neutral: Odoo is the first receiver, but any system that implements the four
endpoints in §5 works with the same app.

## 2. Decisions

| Topic | Decision |
|---|---|
| Card model | Card fixed at the site = **location**. Employee's own phone + login = **person**. |
| Platforms | Android and iPhone, one Flutter codebase. A Mac with Xcode and an iPhone are available. |
| Tap flow | **App-first**: employee opens the app, then taps (iPhone: presses **Scan** first). The app reads the chip UID directly. |
| Server | One configurable **Server URL**; four fixed paths under it. |
| Identity | Username + password sent to `POST /login`, which returns a token. In Odoo: **Badge ID + PIN**. |
| Check-in vs check-out | Configurable per company: **auto** (server toggles) or **manual** (employee picks In/Out). |
| No internet | **Queue** the tap on the phone, send it later; server uses the phone's tap time, flagged offline. |
| Out of radius / fake GPS | **Reject** the tap. |
| Device + IP (Amendment 1, §14) | Each employee is **bound to one approved phone** (device ID, since IMEI is blocked by the OS); every tap records device, OS, public IP and local IP. |
| Languages | English + Arabic (RTL). |
| Phase-1 receiver | Odoo **20** module. |

## 3. The card (inspected 2026-11-17 with NFC Tools)

NXP **NTAG213** (ISO 14443-3A; NfcA, MifareUltralight, Ndef), UID `04:DB:8F:E2:3B:15:90` (7 bytes,
factory-fixed), NXP originality signature valid, not password-protected, writable, 137 bytes NDEF
capacity, currently holds one URI record `https://www.wtechkw.com`.

The app identifies cards by UID only. The stored URI is ignored and will be replaced (§9).

## 4. Architecture

```
 ┌────────────── Phone ──────────────┐            ┌──────── Server (Odoo 20 or other) ───────┐
 │ NFC reader ─► UID                  │  HTTPS     │ /nfc/api/v1/login   Badge ID + PIN → token│
 │ GPS ─► lat/lng/accuracy/mocked     │ ─────────► │ /nfc/api/v1/punch   checks → hr.attendance│
 │ Tap service ─► API client ─► queue │  JSON      │ /nfc/api/v1/status  current state         │
 │ (SQLite, oldest-first retry)       │ ◄───────── │ /nfc/api/v1/logout  revoke token          │
 └────────────────────────────────────┘            └───────────────────────────────────────────┘
```

| Part | Location | Notes |
|---|---|---|
| Flutter app | `~/workspace/flutter/nfc_attendance` | App ID `com.centrixplus.nfc_attendance`. `API.md` at repo root. |
| Odoo module | `~/workspace/projects/projects20/NfcAttendance/nfc_attendance` | Depends on `hr_attendance`. |

Both are new local git repos. Nothing is pushed until asked; nothing is committed until the user has
verified it.

## 5. API contract v1

### 5.1 General

- **Base URL** is configured in the app, e.g. `https://erp.client.com/nfc/api/v1`. Paths below are
  relative to it.
- Requests and responses are JSON (`Content-Type: application/json`). Not JSON-RPC.
- Authenticated calls send `Authorization: Bearer <token>`.
- The app sends `Accept-Language: en` or `ar`; servers should return `message` text in that language.
- All server timestamps are ISO 8601 UTC (`2026-11-17T06:02:11Z`). The app sends `tapped_at` with
  the phone's offset (`2026-11-17T09:02:11+03:00`).
- Every error response has the shape `{"error": {"code": "<code>", "message": "<text for the employee>"}}`.
  Extra fields may be added inside `error` (e.g. `distance_m`, `retry_after_s`).

### 5.2 Endpoints

**`POST /login`**

```json
{ "login": "041234567890", "password": "1234",
  "device": { "id": "<app-install uuid>", "platform": "android", "model": "SM-S928B", "app_version": "1.0.0+1" } }
```
200:
```json
{ "token": "<opaque>", "employee": { "id": 17, "name": "Ahmed Ali" },
  "settings": { "punch_mode": "auto" }, "server_time": "2026-11-17T06:00:00Z" }
```
Errors: `401 invalid_credentials`, `423 locked` (with `retry_after_s`).
Logging in again from the same device ID replaces that device's previous token. Tokens do not
expire in phase 1; they end on logout or when HR revokes them.

**`POST /punch`** (Bearer)

```json
{ "client_uuid": "6f1c2a9e-…",
  "card_uid": "04DB8FE23B1590",
  "action": "auto",
  "tapped_at": "2026-11-17T09:02:11+03:00",
  "offline": false,
  "location": { "lat": 29.3759, "lng": 47.9774, "accuracy_m": 8.5, "is_mocked": false,
                "captured_at": "2026-11-17T09:02:09+03:00" } }
```
- `card_uid`: uppercase hex, no separators.
- `action`: `auto` | `check_in` | `check_out`. The request's `action` decides, whatever the company
  mode: `auto` toggles; an explicit `check_in`/`check_out` is validated. (The app picks `action`
  from `punch_mode`; this keeps queued taps valid across a mode change.)
- `offline`: `true` when the tap is being sent from the queue (the server did not answer at tap time).

200:
```json
{ "result": "check_in", "time": "2026-11-17T06:02:11Z", "site": "Head Office",
  "message": "Checked in at 09:02 — Head Office" }
```

**`GET /status`** (Bearer) → 200:
```json
{ "employee": { "id": 17, "name": "Ahmed Ali" }, "state": "checked_in",
  "since": "2026-11-17T05:02:00Z", "site": "Head Office",
  "punch_mode": "auto", "server_time": "2026-11-17T08:00:00Z" }
```
`since` and `site` are `null` when checked out. Without a token it returns `401 invalid_token` in
the standard error shape; the app's **Test** button relies on this.

**`POST /logout`** (Bearer) → 200 `{ "ok": true }`; the token is revoked.

### 5.3 Error codes

| HTTP | Code | When |
|---|---|---|
| 400 | `bad_request` | Malformed JSON or missing fields |
| 401 | `invalid_credentials` | Login: wrong Badge ID or PIN |
| 401 | `invalid_token` | Missing, unknown or revoked token |
| 423 | `locked` | Too many wrong PINs |
| 403 | `device_not_allowed` | Login or punch from a phone that is not the employee's approved phone (§14) |
| 422 | `unknown_card` | Card not registered, inactive, or another company's |
| 422 | `location_required` | No location in the request |
| 422 | `mock_location` | `is_mocked` is true |
| 422 | `out_of_range` | Outside the site radius (includes `distance_m`) |
| 422 | `too_old` | Offline tap older than the company limit |
| 422 | `invalid_time` | Tap time more than 5 minutes in the future |
| 422 | `older_than_last` | Tap time earlier than the employee's latest attendance event |
| 422 | `too_soon` | Within the minimum gap after the last attendance event |
| 422 | `already_checked_in` | Manual mode `check_in` while checked in (or Odoo single check-in blocks the check-out) |
| 422 | `not_checked_in` | Manual mode `check_out` while checked out |
| 422 | `cannot_record` | The server's own attendance rules refuse the record (e.g. HR edited attendances so the close would overlap). Final — retrying cannot help. |
| 5xx | (any) | Server fault — the app queues and retries |

### 5.4 Idempotency and time

- The server stores `client_uuid`. A repeat request returns the **original** response (same status
  and body) and creates nothing.
- **Online** (`offline: false`): the attendance time is the **server's** clock.
- **Offline** (`offline: true`): the attendance time is `tapped_at`, and the record is flagged offline.

## 6. Mobile app

### 6.1 Screens

1. **Server setup** (first launch only): Server URL field + **Test** (expects `401 invalid_token`
   in the standard shape from `GET /status`).
2. **Login**: "Employee ID" and "PIN / Password".
3. **Home**: employee name; status from `/status` ("Checked in since 08:02 — Head Office" /
   "Checked out"); GPS indicator; "N not sent" badge.
   - Auto mode — Android: "Hold your phone to the card", NFC listening whenever Home is visible.
     iPhone: large **Scan card** button opens the system NFC sheet.
   - Manual mode: **Check In** / **Check Out** buttons first, then tap/scan.
   - Blocking banners: location permission off (**Open Settings**), NFC off (Android), not logged in.
4. **Result**: full-screen green ✓ or red ✗ with the server `message`, vibration, auto-closes after 4 s.
5. **History**: last 50 taps from local storage — Sent ✓ / Waiting ⏳ / Rejected ✗ + reason.
6. **Settings**: Server URL (changing it logs out), language EN/AR, Logout, app version, permission status.

### 6.2 Tap flow

1. Home becomes visible → start the GPS stream so a fix is ready before the tap.
2. Card read → UID as uppercase hex. The same UID within 10 s of the previous read is ignored.
3. Location: use the latest fix if ≤ 30 s old; otherwise wait up to 10 s for one. No fix →
   "No GPS signal — move near a window"; **nothing is recorded or sent**.
4. Build the punch (new `client_uuid`, `tapped_at` = now with offset) and store it locally as Waiting.
   **If older taps are already Waiting**, the new tap is queued behind them with `offline: true` and
   the queue is flushed oldest-first — it is never sent ahead of them (otherwise the older taps
   would be rejected as `older_than_last`). The result screen shows "Saved — will send automatically"
   and History updates as the queue drains.
5. Otherwise send with a 10 s timeout:
   - 200 → Sent; show green result; refresh status.
   - 4xx → Rejected; show red result with the server message; never retried. 401 also routes to Login.
   - No response / 5xx → stays Waiting with `offline: true` for later sends; show "Saved — will send automatically".

### 6.3 Offline queue

- SQLite table: `client_uuid`, request JSON, status (waiting / sent / rejected), attempts,
  last error, created_at, result message. History reads the same table; non-waiting rows beyond the
  newest 50 are pruned.
- Sent strictly **oldest first, one at a time**. A 401 pauses the queue until the employee logs in again.
- Triggers: app start and resume, connectivity regained, every 60 s while open, after each new tap.
- Phase 1 sends only while the app is open (no background sync).
- Logout with waiting taps asks "Discard N unsent taps?" — logout proceeds only on confirm.

### 6.4 Platform specifics

- **Android**: NFC reader mode while Home is visible, so the system does not open the card's URL.
  Mock-location detection via the location API's mocked flag.
- **iPhone**: Core NFC tag reading session (MIFARE/ISO 14443 polling) started by **Scan card**.
  Needs the NFC Tag Reading capability (`com.apple.developer.nfc.readersession.formats` = `TAG`),
  `NFCReaderUsageDescription`, and "when in use" location permission. iPhone 7 or newer.
  Mock-location detection is limited on iOS (sent when the platform reports it, otherwise `false`).

### 6.5 Stack and storage

Flutter 3.44.6 (workspace toolchain). Riverpod + go_router (as in CentrixHR), `nfc_manager`,
`geolocator`, `dio`, `sqflite`, `flutter_secure_storage` (token, device ID), `connectivity_plus`,
`uuid`, `easy_localization` (EN/AR RTL). Exact versions are fixed in the implementation plan.

## 7. Odoo 20 module `nfc_attendance`

### 7.1 Data

- **`nfc.attendance.card`** (Attendances → NFC Cards, a top-level entry so officers can reach it
  without exposing the rest of Configuration): `name` (site), `card_uid`
  (normalised uppercase hex, unique; not named `uid` to avoid clashing with Odoo's `uid`), `latitude`, `longitude`, `radius_m` (default 100),
  `company_id`, `active`, `note`.
- **`nfc.attendance.token`**: `employee_id`, `token_hash` (SHA-256; raw token never stored),
  `device_id`, `platform`, `model`, `app_version`, `last_used`, `active`.
- **`nfc.attendance.punch`** (Attendances → Reporting → NFC Taps): every request including rejected
  ones — `employee_id`, `card_id`, raw `card_uid`, `client_uuid` (unique), requested `action`,
  `result` (check_in / check_out / rejected), `reject_code`, `message`, `tapped_at`, `received_at`,
  `offline`, `latitude`, `longitude`, `accuracy_m`, `distance_m`, `is_mocked`, `token_id`,
  `attendance_id`, stored response (status + body, for idempotent replays). Filter: Rejected.
- **`hr.employee`**: `nfc_failed_pin_count`, `nfc_locked_until`; form tab **NFC App** listing
  tokens (device, last used, **Revoke**) and lock state (**Unlock**).
- **`hr.attendance`**: `in_mode` / `out_mode` gain `nfc`. NFC punches fill the existing
  `in_/out_latitude`, `in_/out_longitude` and `in_/out_location` (= site name) fields, plus
  `in_/out_nfc_card_id` and an `nfc_offline` flag.
- **Company settings** (Attendances settings): `nfc_punch_mode` (auto/manual, default auto),
  `nfc_offline_max_hours` (default 24), `nfc_min_gap_seconds` (default 60).

### 7.2 Login

Find the employee by **Badge ID** (`barcode`). No match or more than one match →
`invalid_credentials`. If `nfc_locked_until` is in the future → `423 locked`. Wrong PIN →
increment the counter; the 5th consecutive failure locks for 15 minutes. Correct PIN → reset the
counter, create the token (32 random bytes, URL-safe), replace any active token for the same
`device_id`, return §5.2.

### 7.3 Punch checks (in order; first failure wins)

1. Token missing/unknown/revoked → `401 invalid_token`.
2. `client_uuid` already stored → replay the stored response.
3. Card UID not an active card of the employee's company → `unknown_card`.
4. No location → `location_required`; `is_mocked` → `mock_location`.
5. Haversine distance from the card's point: reject `out_of_range` when
   `distance_m > radius_m + min(accuracy_m, 50)`.
6. Event time = server now (online) or `tapped_at` (offline):
   offline and older than `nfc_offline_max_hours` → `too_old`; more than 5 min in the future →
   `invalid_time`; earlier than the employee's latest check-in/check-out → `older_than_last`.
7. Event time within `nfc_min_gap_seconds` of the latest check-in/check-out → `too_soon`
   (message names the previous event, e.g. "Already checked in at 08:02").
8. Action — auto: open attendance → check-out, else check-in. Manual: `check_in` while checked in
   → `already_checked_in`; `check_out` while checked out → `not_checked_in`. Odoo's company
   **single check-in** setting is honoured the way `_attendance_action_change` does
   (check-out refused → `already_checked_in`).
9. Create (`check_in` = event time) or close (`check_out` = event time) the `hr.attendance` with
   `mode = nfc` and GPS/site fields; log the punch with the response; return 200.

Every outcome, including rejections, writes one `nfc.attendance.punch` row.

### 7.4 HTTP layer

- Routes `/nfc/api/v1/{login,punch,status,logout}`, `type="http"`, `auth="none"`, `csrf=False`,
  JSON responses via `request.make_json_response(..., status=...)`.
- Work is done as superuser after the token/PIN check, scoped to the employee's company.
- **Deploy requirements:** one database per server or a `dbfilter` that resolves to one (the app
  sends no database name); HTTPS (the app refuses plain `http://` except for `localhost`,
  `127.0.0.1` and `10.0.2.2`, which are for local testing only).
- Response messages are translatable; Arabic strings ship in the module's `i18n/ar.po`.

### 7.5 Access

- Attendance officers: read/write cards, read taps and tokens, revoke tokens, unlock employees.
- Attendance managers: also delete cards. Changing the NFC settings needs Odoo's Settings right
  (Administration), as for every Odoo settings page.
- The NFC menus (Cards, Taps) are visible to attendance officers, not only administrators.
- Uses Odoo 20's `security/ir.access.csv` format (`operation` column, ordered `crud` subset).

## 8. Error handling summary

| Situation | App shows | Stored as |
|---|---|---|
| No GPS fix in 10 s | "No GPS signal — move near a window" | nothing |
| Location permission off | Blocking banner + Open Settings | nothing |
| NFC off (Android) | Banner "Turn on NFC" | nothing |
| No network / timeout / 5xx | "Saved — will send automatically" | Waiting |
| 4xx rejection | Red result with server message | Rejected |
| 401 | Login screen | queue paused |

## 9. Card setup per site

1. In our app on Android: Settings → **Prepare wall card** → confirm → tap the card. It replaces the
   card's content with our MIME record (`application/vnd.centrixplus.nfcatt`) + an Android
   Application Record for `com.centrixplus.nfc_attendance`, and shows the card UID. On Android, a
   tap with the app closed then opens our app. (Added 2026-11-17 after the spike: NFC Tools cannot
   write the custom MIME record that the one-tap launch needs.)
2. Odoo → NFC Cards: add the UID, the site's latitude/longitude and radius.
3. At go-live: NFC Tools → Other → **Set password** to block rewriting. Never use **Lock** (permanent).

## 10. Build order

1. **Spike on the Galaxy S24 Ultra (SM-S928B)**: show UID + GPS on screen. Confirms Android reader
   mode suppresses the card URL, and whether an AAR launch can deliver the tag in the same tap
   (one-tap punch) or needs a second tap.
2. **Odoo module** with tests.
3. **Full app**: setup, login, home, result, history, settings, queue, EN/AR.
4. **End-to-end on the S24** with the real card against a local Odoo 20 (adb reverse), including a
   mock-location test; screenshot every screen.
5. **iPhone** build on the Mac and test on an iPhone.

## 11. Testing

- **Odoo**: tests over the HTTP routes for login success/failure/lockout/unlock, every reject code
  in §5.3, idempotent replay, revoke → 401, auto and manual modes, offline ordering, single
  check-in. Run on a **fresh install** and the **upgrade path**, and on the target server's Odoo
  build before deploying (the local checkout can differ from the prod image).
- **Flutter**: unit tests for UID formatting, API client error mapping (stubbed HTTP), queue
  ordering/retry/pause-on-401/prune, location freshness rules, tap debounce. Widget tests for Home
  states (auto/manual, banners, waiting badge) and RTL layout.
- **On device**: real card on the S24; screenshot each screen in EN and AR; fake-GPS test; airplane
  mode → queue → reconnect → sent in order.

## 12. Out of scope (phase 1)

Background sync while the app is closed · reading the IMEI (blocked by Android 10+ and iOS; MDM-managed company phones would be a separate project) · iPhone auto-launch from a card tap (universal links) ·
NXP originality-signature verification · check-in selfie · multiple Odoo databases per server ·
card registration inside the app · token expiry.

## 13. To verify during implementation

- AAR launch on Android: whether the launching tap's tag is available to the app (one tap) or a
  second tap is needed. The spike decides; the flow in §6.2 works either way.
- `nfc_manager` current major version API for reading the UID on both platforms, and iOS reading
  of NTAG213 UID through it.
- iOS mocked-location reporting through `geolocator`.
- Odoo 20 `single_check_in` behaviour on the target build, and whether `hr.employee.barcode` is
  unique across companies there.

## 14. Amendment 1 — device binding and IP address (2026-11-17)

Requested after the first build: capture the phone's IP address and IMEI.

**IMEI is not available.** Since Android 10, reading the IMEI or serial number needs
`READ_PRIVILEGED_PHONE_STATE`, which only system, carrier-privileged or device-owner (MDM) apps can
hold; iOS has no IMEI API at all. Instead the app sends a **hardware ID** that survives app
reinstalls: Android `Settings.Secure.ANDROID_ID` (stable per device + signing key + user; changes on
factory reset), iOS `identifierForVendor` (cached in the Keychain-backed secure storage so a
transient `nil` does not change it). Company-owned MDM phones with real IMEI are out of scope.

### 14.1 Contract changes (additive to §5)

- `POST /login` → `device` gains **`hardware_id`** (required) and **`os_version`**
  (e.g. `"17"`, `"18.1"`). Missing `hardware_id` → `400 bad_request`.
- `POST /punch` gains **`device`**: `{ "hardware_id": "…", "local_ip": "192.168.1.25" }`.
  `local_ip` is the phone's own IPv4 (Wi-Fi first, else mobile data, else `null`).
- New error **`403 device_not_allowed`** (login and punch), standard error shape, final like any 4xx.
  Message: "This phone is not registered for you. Ask HR to approve it."
- The server records the **public IP it sees** for every request (the app cannot fake it). Behind
  a reverse proxy, Odoo needs `proxy_mode = True` so the phone's IP (from `X-Forwarded-For`) is used.

### 14.2 Binding rules (server)

- New model **`nfc.attendance.device`**: `employee_id`, `hardware_id`, `platform`, `model`,
  `os_version`, `state` (`approved` | `pending`), `first_seen`, `last_seen`, `approved_by`,
  `approved_on`. Unique (`employee_id`, `hardware_id`).
- New company setting **`nfc_device_binding`** (Boolean, default **on**). When off, devices are
  still recorded but never block.
- **Login** (after the PIN check succeeds):
  - Employee has no approved device → register this one as **approved** (first phone).
  - `hardware_id` matches the approved device → OK, update `last_seen`/model/OS.
  - Otherwise → create or refresh a **pending** device, issue no token, return
    `403 device_not_allowed`. The failed-PIN counter is not touched (the PIN was right).
- **Approve** (button on a pending device, employee form → NFC App tab, attendance officers):
  the new phone becomes the single approved device; the previous approved device is removed and
  **all its tokens are revoked**.
- **Punch** — new check right after the token check (§7.3 step 1), before replay:
  binding on and the token's device is no longer approved → `401 invalid_token` (it was replaced);
  request `device.hardware_id` differs from the token's device → `403 device_not_allowed`.
  Replay (step 2) still returns the stored response for a known `client_uuid` from the same token.
- **Recording**: `nfc.attendance.punch` gains `hardware_id`, `local_ip`, `remote_ip`, `device_id`
  (→ `nfc.attendance.device`). `hr.attendance` fills the existing `in_/out_ip_address` with the
  **public** IP and `in_/out_browser` with
  `"NFC App <app_version> · <platform> <os_version> · <model> · local <local_ip>"`.
  The token stores the device it was issued to.

### 14.3 App changes

- Read the hardware ID: Android via the existing `nfc_attendance/system` MethodChannel
  (`getAndroidId` in `MainActivity.kt`); iOS via `device_info_plus` `identifierForVendor`, cached.
- Read `os_version` with `device_info_plus`; `local_ip` with `dart:io` `NetworkInterface.list`
  (IPv4, non-loopback; prefer `wlan*`/`en0`, then any) — captured at tap time, stored with the
  queued punch so a later resend keeps the tap-time value.
- `403 device_not_allowed`: on Login show the server message (stay on Login); on a tap it is a
  final rejection like any 4xx.
- Settings shows **This phone's ID** (hardware ID, selectable) so HR can match the pending device.
- EN + AR strings for every new text.

## 15. Amendment 2 — employee photo on every tap (2026-11-17)

User decisions: photo on **check-in and check-out**; **required**, with an **on-device face check**
(exactly one face); photos **kept forever** (no deletion job).

### 15.1 Contract changes (additive to §5 and §14)

- `POST /login` and `GET /status` → `settings` gains **`photo_required`** (boolean). The app opens
  the camera only when it is `true`, so other platforms that do not want photos send `false`.
- `POST /punch` gains **`photo`** (object, or absent):
  `{ "mime": "image/jpeg", "data": "<base64 JPEG>", "taken_at": "<ISO with offset>", "faces": 1 }`.
  The JPEG is at most 640 px on its long side, quality ≈ 70 (typically 40–90 KB); the server
  rejects anything over **1 MB decoded**.
- New 422 codes (final, standard shape):
  - **`photo_required`** — `photo_required` is on and the request has no photo.
  - **`invalid_photo`** — not a decodable JPEG/PNG, or over 1 MB.
- The server cannot verify faces; it records the app's `faces` count as reported.
- Check order (§7.3): the photo checks run **after** the device check (§14.2) and **before** the
  card check, so a tap without a required photo is rejected before anything else is evaluated.

### 15.2 Server (Odoo)

- Company setting **`nfc_photo_required`** (Boolean, default **on**), shown in the NFC App settings
  block and returned as `settings.photo_required`.
- Check-in photo → Odoo's native **`hr.attendance.in_image`** (Check-In Image). Check-out photo →
  new **`hr.attendance.nfc_out_image`** (Binary, `attachment=True`, "Check-Out Image"), shown next to
  the native image on the attendance form.
- The tap row `nfc.attendance.punch` stores the photo too (`photo`, Binary, `attachment=True`) and
  `photo_faces`; the NFC Taps list/form shows a thumbnail. Rejected taps keep their photo as evidence.
- Photo fields are readable by attendance officers only.
- Odoo 20: write binaries as `odoo.tools.BinaryBytes(raw_bytes)` (not base64 strings) — see how
  `_attendance_action_change` sets `in_image`.
- No retention job (kept forever).

### 15.3 App

- Flow per tap: card read (debounce) → **in-app front camera** full screen (no gallery access),
  3-second countdown with auto-capture plus a shutter button → on-device face detection
  (Google ML Kit, offline) on the still image → exactly **1 face** → resize/compress → send (or
  queue). 0 faces → "Face not visible — try again"; 2+ faces → "Only you should be in the photo";
  the employee can retry; **Cancel discards the tap** (nothing stored or sent).
- GPS is captured in parallel while the camera is open; `tapped_at` stays the card-read moment.
- The photo travels inside the queued punch (same `client_uuid`), so offline taps keep their photo.
- Manual mode: choose In/Out → tap card → camera. The one-tap launch (Android) uses the same flow.
- Permissions: camera on Android; `NSCameraUsageDescription` on iOS. ML Kit needs iOS 15.5+
  (arm64 devices) — raise the iOS deployment target if needed.
- EN + AR strings for every new text.
