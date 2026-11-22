# Plan 3 — Full Flutter app

- **Date:** 2026-11-17
- **Spec:** `docs/superpowers/specs/2026-11-17-nfc-attendance-design.md` (§5 client side, §6, §8, §11 Flutter)
- **Builds on:** Plan 1 spike (`lib/core/nfc/*`, `MainActivity.kt`, manifest) — kept and reused.
- **Rules:** test-first (write test → see it fail → implement → see it pass). No commits.

## Contract update (lead, during implementation)

- New final 422 code `cannot_record` → `ErrorCodes.cannotRecord`, tested in the API and queue tests.
- §6.2 step 4: if taps are already Waiting, a new tap is stored behind them with `offline: true`,
  the result is "Saved — will send automatically" and the queue flushes in the background; only
  with nothing waiting is the tap sent at once with `offline: false` (`TapService`, tests
  "never overtakes").
- `action` decides regardless of company mode (documented in `API.md`).

## Device findings applied

| Finding (S24 spike) | Applied in |
|---|---|
| Holding the card re-reads it every ~1 s | `TapDebouncer` (10 s since the previous read of the same UID, ignored reads included) |
| GPS first fix ~1.4 s, then ~50 ms; 19–34 m indoors | `LocationTracker` stream starts when Home becomes visible |
| OS turns reader mode off on pause | `HomeScreen` restarts the NFC session on resume |
| Launch-tag one-tap unverified | `LaunchTagChannel` taken at bootstrap + listened on Home; harmless if never delivered |

## Packages

| Package | Constraint | Why |
|---|---|---|
| flutter_riverpod | ^2.6.1 | state (as CentrixHR) |
| go_router | ^14.8.1 | routing + redirect on session |
| dio | ^5.8.0 | HTTP |
| flutter_secure_storage | ^9.2.4 | token, device ID, server URL |
| easy_localization | ^3.0.7 | EN/AR + RTL |
| intl | ^0.20.2 | time formatting |
| nfc_manager | 4.2.1 (pinned) | NFC |
| geolocator | ^14.0.2 | GPS + mocked flag |
| sqflite | 2.4.5 (exact; newer ones < 2 weeks old) | queue/history |
| connectivity_plus | ^7.3.2 | "connectivity regained" trigger |
| uuid | ^4.6.0 | `client_uuid`, device ID |
| package_info_plus | ^10.2.2 | `app_version` |
| device_info_plus | ^13.3.0 | `model` |
| dev: sqflite_common_ffi | 2.4.5 (exact) | real SQLite in unit tests |
| dev: fake_async | SDK-pinned | GPS wait / timers in tests |

## File map

```
lib/
  main.dart                          bootstrap + runApp
  app/
    bootstrap.dart                   load session, open DB, take launch tag, build overrides
    app.dart                         MaterialApp.router + easy_localization + language sync
    router.dart                      go_router routes + session redirect
    providers.dart                   Riverpod graph (store, api, queue, tracker, session, nfc)
    theme.dart                       Material 3 theme
  core/
    api/api_outcome.dart             sealed ApiOk / ApiRejected / ApiUnreachable
    api/api_models.dart              Employee, PunchMode, PunchAction, Login/Punch/Status results, DeviceInfo
    api/error_codes.dart             §5.3 code constants
    api/attendance_api.dart          dio client: login, punch, status, logout, probe
    api/server_probe.dart            Test-button result
    config/server_url.dart           normaliseServerUrl (trim, scheme, trailing slashes)
    time/iso_time.dart               isoWithOffset (tapped_at / captured_at), parseServerTime
    l10n/app_language.dart           supported locales + current code for Accept-Language
    storage/key_value_store.dart     KeyValueStore + secure + in-memory impls
    storage/session_store.dart       typed persistence of url/token/employee/mode/device id
    device/device_descriptor.dart    `device` block for /login
    location/gps_fix.dart            fix value + JSON
    location/location_access.dart    permission/service state + GeolocatorPlatformGateway
    location/location_tracker.dart   ≤30 s reuse, ≤10 s wait, stream lifecycle
    queue/tap_record.dart            row model + TapStatus
    queue/tap_store.dart             TapStore interface
    queue/sqlite_tap_store.dart      sqflite implementation (+ prune)
    queue/punch_queue.dart           oldest-first, one-at-a-time, pause-on-401
    queue/queue_triggers.dart        start/resume, connectivity regained, 60 s timer
    session/session.dart             Session value
    session/session_controller.dart  login/logout/expire/change server
    tap/tap_debouncer.dart           10 s same-UID
    tap/punch_action_resolver.dart   auto vs manual action
    tap/tap_outcome.dart             sealed outcomes for the UI
    tap/tap_service.dart             read → location → store → flush → outcome
    nfc/ (existing) + nfc_system_channel.dart (open NFC settings)
  features/
    setup/server_setup_screen.dart   URL + Test (first launch and Settings → change)
    login/login_screen.dart          Employee ID + PIN
    home/home_state.dart             immutable view state
    home/home_controller.dart        status, banners, GPS, badge, manual selection, taps
    home/home_screen.dart            lifecycle: NFC session, GPS stream, launch tags
    home/home_view.dart              pure view (widget-tested)
    home/widgets/*.dart              banners, status card, indicators, tap panel
    result/result_overlay.dart       full-screen ✓/✗/⏳, vibration, 4 s auto-close
    history/history_screen.dart      last 50 rows
    settings/settings_screen.dart    URL, language, permissions, version, logout
    settings/logout_flow.dart        "Discard N unsent taps?" + logout
    settings/prepare_card_dialog.dart Android: write buildCardMessage(), show UID
assets/translations/en.json, ar.json
android: network_security_config.xml, manifest label/backup/cleartext, MainActivity NFC-settings method
ios: Info.plist keys + ATS, Runner.entitlements wired via CODE_SIGN_ENTITLEMENTS
API.md, README.md
```

## Tasks (in order)

1. Delete `lib/spike/`; add packages; confirm `sqflite_common_ffi` runs on this host.
2. `server_url` + `iso_time` — tests then code.
3. API: outcome/models/codes, `AttendanceApi` with a stub dio adapter — every §5.3 code →
   `ApiRejected`, 5xx/timeout/connection error/garbled 200 → `ApiUnreachable`, headers
   (Bearer, Accept-Language, JSON), probe (401 `invalid_token` = OK).
4. Queue: `SqliteTapStore` + `PunchQueue` — oldest first, one at a time (no overlap even when
   flush is called concurrently), stop at first unreachable, `offline: true` + same
   `client_uuid` on resend, 4xx → rejected and continue, 401 → pause (fresh tap rejected,
   queued tap stays waiting), resume after login, prune to newest 50 non-waiting rows.
5. Location: `LocationTracker` freshness tests with a fake stream + fake clock.
6. Tap: debouncer, action resolver, `TapService` (no GPS → nothing stored).
7. Session store/controller, device descriptor, providers, router, bootstrap.
8. Screens: setup, login, home (view + controller + screen), result, history, settings,
   prepare wall card, logout flow. Translations EN/AR.
9. Widget tests: Home auto (Android/iOS), manual, banners, waiting badge, RTL render.
10. Platform config: Android cleartext + label; iOS Info.plist/ATS/entitlements.
11. `API.md`, `README.md`.
12. Gate: `flutter analyze` clean, `flutter test` green; debug APK on the S24; screenshot of
    Server setup; `./gradlew --stop`.

## Follow-up A — Amendment 1: device binding and IP address (spec §14)

Contract (§14.1): `/login` `device` gains `hardware_id` (required) + `os_version`; `/punch` gains
`device {hardware_id, local_ip}`; new final `403 device_not_allowed` (login and punch).

### File map

```
lib/core/device/system_channel.dart     (renamed from core/nfc/nfc_system_channel.dart)
                                        openNfcSettings + getAndroidId
lib/core/device/hardware_id.dart        HardwareIdReader: Android ANDROID_ID (not cached);
                                        iOS identifierForVendor cached in secure storage;
                                        unavailable → app-install ID, cached (never changes later)
lib/core/device/local_ip.dart           pickLocalIpv4 (wlan*/en0 first, then any; IPv4, no
                                        loopback/link-local) + localIpv4() over NetworkInterface.list
lib/core/device/device_descriptor.dart  + hardware_id, os_version
lib/core/api/api_models.dart            DeviceInfo + hardwareId/osVersion
lib/core/api/error_codes.dart           + device_not_allowed
lib/core/tap/punch_body.dart            + device {hardware_id, local_ip}
lib/core/tap/tap_service.dart           captures the punch device block at tap time
lib/app/bootstrap.dart, providers.dart  hardwareIdProvider (read once at start)
lib/features/login/login_screen.dart    403: server message + this phone's ID, stay on Login
lib/features/settings/settings_screen.dart  "This phone's ID" (selectable, copy)
android MainActivity.kt                 getAndroidId on nfc_attendance/system
assets/translations/*.json, API.md
```

### Tasks (test-first)

1. Tests: hardware ID reader (cache/fallback per platform), local IP picker, API login body
   (`hardware_id`, `os_version`), 403 in the code table, queue: 403 final and not pausing,
   tap body `device` block, resend keeps the tap-time `local_ip`, Login 403 stays on Login.
2. Implement; EN/AR strings; Settings tile; Kotlin method.
3. API.md: fields, 403, binding behaviour, public IP / `proxy_mode`, why no IMEI.
4. Gate: analyze clean, tests green; build debug APK (not installed); `./gradlew --stop`.

## Follow-up B — Amendment 2: employee photo on every tap (spec §15)

Contract (§15.1): `settings.photo_required` on `/login` and `/status`; `/punch` gains
`photo {mime, data(base64 JPEG), taken_at, faces}`; new final 422 `photo_required`, `invalid_photo`
(server limit 1 MB decoded).

Packages (published ≥ 2 weeks before 2026-11-17): `camera` ^0.12.2 (→ 0.12.2; camerax 0.7.6+1,
avfoundation 0.11.1), `google_mlkit_face_detection` ^0.15.1 (1.0.x too new; commons 0.13.0),
`image` 4.12.0 (pure Dart resize/encode, testable on the host); overrides `archive` 4.6.0,
`camera_web` 0.3.5+7. Baseline APKs: debug 217,051,966 B; release arm64 19,808,911 B.

### File map

```
lib/core/photo/punch_photo.dart        PunchPhoto value + §15.1 JSON
lib/core/photo/photo_compressor.dart   compressPhoto: EXIF orientation baked, ≤ 640 px long side,
                                       JPEG q70, lower quality until ≤ 1,000,000 B, else error
lib/core/photo/face_rule.dart          exactly one face rule
lib/core/photo/photo_processor.dart    face count → rule → compress → PunchPhoto (or a problem)
lib/core/photo/camera_session.dart     CameraSession interface + CapturedImage + CameraUnavailable
lib/core/photo/camera_plugin_session.dart  front camera via `camera` (only file touching it)
lib/core/photo/face_counter.dart       FaceCounter interface + ML Kit implementation
lib/features/photo/photo_capture_screen.dart  full screen, 3 s countdown + shutter, retry, Cancel
lib/core/tap/tap_service.dart          photo step: GPS in parallel, Cancel → nothing stored,
                                       debounce reset; tapped_at stays the read time
lib/core/queue/sqlite_tap_store.dart   finished rows drop photo.data (waiting rows keep it)
api models / session / home            photo_required read from login + status, cached
Android CAMERA permission; iOS NSCameraUsageDescription, deployment target 15.5, Podfile
```

### Tasks (test-first)
1. Tests for compressor, face rule, processor, capture screen (fake camera + counter), tap flow
   with photo, store stripping, settings parsing, new codes.
2. Implement; EN/AR strings; Home hint; platform config.
3. API.md + README; gate; debug APK (not installed); APK sizes; `./gradlew --stop`.

## Follow-up C — TapIn: rename, design system, company code (TapIn spec §7, §5.6)

Sources: TapIn SaaS spec `projects20/TapIn/docs/superpowers/specs/2026-11-17-tapin-saas-design.md`
§5.6 + §7; design system `tapin-ds` (tokens.json, README); app artboards
`App{Company,Login,Home,Camera,Result,History,Settings,HomeAr}`. Master checked live:
`GET /tapin/api/v1/company/<code>` → `{code,name,logo_url,api_base_url,status}`, 404 `not_found`;
states `provisioning|active|grace|suspended`.

### Decisions
- App stays Dart package `nfc_attendance`; Android `applicationId`/`namespace` and iOS bundle ID
  become `com.centrixplus.tapin`; label/display name `TapIn`; AAR record → `com.centrixplus.tapin`
  (MIME record unchanged). Method channel names unchanged (internal).
- Master base = `String.fromEnvironment('TAPIN_MASTER_URL', defaultValue:
  'https://tapin-account.karrix.com')`; directory = `<master>/tapin/api/v1/company/<code>`.
- Company `active`/`grace` → Continue; `provisioning`/`suspended` → message, no Continue; 404 →
  "We can't find that company code"; 429 → wait; no answer → check connection.
- QR: `tapin://company/<code>` (a bare valid code is also accepted). Code rule §5.3.
- `403 subscription_inactive`: final; Login shows the message and stays.
- Fonts bundled (OFL): IBM Plex Sans 400/500/600, Plex Sans Arabic 400/500/600, Plex Mono 600.
- QR scanner `mobile_scanner` ^7.5.0 (2026-11-01). Icons via `flutter_launcher_icons` 0.14.4
  from PNGs drawn with PIL (NFC motif). Splash hand-made (brand blue + motif).
- Debug builds only: long-press the NFC motif simulates a card read (UID of the test card) so
  the camera/result screens can be exercised without a physical tap. Not in release builds.

### File map (new / rewritten)
```
lib/app/tokens.dart                 colours, radii, spacing, text styles from tokens.json
lib/app/theme.dart                  ThemeData from tokens (Plex Sans / Plex Sans Arabic by locale)
lib/core/directory/company.dart     Company + status
lib/core/directory/company_code.dart  code rule + QR parsing
lib/core/directory/directory_api.dart lookup → CompanyLookup (found/notFound/inactive/...)
lib/core/config/tapin_config.dart   master URL constant
lib/features/company/company_screen.dart, qr_scan_screen.dart, company_badge.dart
lib/features/common/nfc_motif.dart, tapin_widgets.dart (cards, buttons, back header, chips)
lib/features/{setup,login,home,photo,result,history,settings}/…  restyled to the artboards
assets/fonts/*, assets/branding/* (icon sources)
```

### Tasks (test-first where there is logic)
1. Rename (test: AAR package) + Android/iOS IDs + MainActivity package move.
2. Directory: code rule, QR parsing, lookup error mapping (stub HTTP) → tests first.
3. Session: company stored; choose/change company; custom server clears company → tests.
4. `subscription_inactive` code (+ Login behaviour) → tests.
5. Tokens/theme/fonts; shared widgets; restyle every screen; EN/AR strings; widget tests EN + AR.
6. Icons + splash. 7. Gate; debug + release arm64 APKs; install on the S24; screenshots EN/AR.
