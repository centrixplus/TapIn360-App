# TapIn360 app: store privacy answers

For filling in **Google Play → App content → Data safety** and **App Store Connect → App Privacy**.
Built from the code on 2026-11-22 (app `com.centrixplus.tapin360`, server modules `nfc_attendance` +
`tapin_tenant`). Re-check this file whenever the app starts sending something new.

## URLs to paste

| Store field | URL |
|---|---|
| Privacy policy (Play: App content → Privacy policy; Apple: Privacy Policy URL) | `https://tapin360.co/en/app/privacy` (Arabic: `https://tapin360.co/ar/app/privacy`) |
| Support (Apple: Support URL; Play: store listing contact website) | `https://tapin360.co/en/support` (Arabic: `https://tapin360.co/ar/support`) |
| Account / data deletion (Play: Data safety → "Delete account URL") | `https://tapin360.co/en/delete-account` (Arabic: `https://tapin360.co/ar/delete-account`) |
| Contact email | `info@tapin360.co` |

The pages exist only after the website is redeployed with this change. The app opens the same three
pages from **Settings** in its current language (`lib/core/config/tapin_config.dart`, `websitePageUrl`).

## What the app sends (verified in the code)

| Moment | Fields | Code |
|---|---|---|
| Company lookup | company code (path), `Accept-Language` → `account.tapin360.co` | `lib/core/directory/directory_api.dart` |
| `POST /login` | `login` (Employee ID), `password` (PIN), `device.{id (app-install UUID v4), platform, model, app_version, hardware_id (Android `ANDROID_ID` / iOS `identifierForVendor`), os_version}` | `lib/core/api/attendance_api.dart:47`, `lib/core/api/api_models.dart:48`, `lib/core/device/device_descriptor.dart`, `lib/app/bootstrap.dart:30` |
| `POST /punch` | `client_uuid`, `card_uid`, `action`, `tapped_at`, `offline`, `location.{lat, lng, accuracy_m, is_mocked, captured_at}`, `device.{hardware_id, local_ip}`, `photo.{mime, data (JPEG ≤ 640 px), taken_at, faces}` when the employer requires photos | `lib/core/tap/punch_body.dart`, `lib/core/location/gps_fix.dart`, `lib/core/photo/punch_photo.dart`, `lib/core/device/local_ip.dart` |
| `GET /status`, `POST /logout` | Bearer token only (`{}` body on logout) | `lib/core/api/attendance_api.dart:67-75` |
| Google ML Kit (SDK) | Google's own usage/diagnostic metrics (see below); no images | `pubspec.yaml` (`google_mlkit_face_detection` 0.15.1 → Android `com.google.mlkit:face-detection:16.1.7`, bundled model; iOS `GoogleMLKit/FaceDetection`), `mobile_scanner` 7.5.0 (Android: bundled `com.google.mlkit:barcode-scanning:17.3.0`; iOS: Apple Vision) |

The server also records, without the app sending it: the request's **public IP** (`nfc.attendance.punch.remote_ip`,
`hr.attendance.in/out_ip_address`, `nfc.attendance.device.last_ip`), the distance from the site, and the phone
model / OS / app version in `hr.attendance.in/out_browser`.

## Google Play: Data safety

General questions:

| Question | Answer | Why |
|---|---|---|
| Does the app collect or share any required user data types? | **Yes** | Location, photos, IDs (below). |
| Is all user data encrypted in transit? | **Yes** | HTTPS only. Android: `network_security_config.xml` refuses cleartext except `localhost`, `127.0.0.1`, `10.0.2.2` (local testing); the app refuses `http://` server URLs for any other host (`lib/core/config/server_url.dart` `isInsecureServerUrl`, used for custom servers and directory answers). iOS: ATS default with only `NSAllowsLocalNetworking`. Google states ML Kit encrypts its data in transit with HTTPS. |
| Do you provide a way for users to request that their data is deleted? | **Yes** | `https://tapin360.co/en/delete-account` (HR or email; see that page). |
| Account creation | Accounts are **created by the employer** in its portal; the app has no sign-up, only log-in with Employee ID + PIN. Pick the option that says the app does not let users create an account (users log in with accounts created outside the app). **Confirm the exact option wording in the form.** | `lib/features/login/login_screen.dart` (no sign-up screen) |

Data types:

| Play category → type | Collected | Shared | Processed ephemerally | Required or optional | Purposes | Notes / code |
|---|---|---|---|---|---|---|
| Location → **Precise location** | Yes | No | No (stored with the tap on the server) | Required | App functionality; Fraud prevention, security and compliance (site radius, mock-location check) | `gps_fix.dart`, `location_gateway.dart` (high accuracy, while-in-use only). No approximate-only declaration needed: the app blocks taps on approximate permission. |
| Photos and videos → **Photos** | Yes, only when the employer turns photos on (default **on** for new portals: `res.company.nfc_photo_required` default `True`) | No | No (kept on the tap and attendance record) | Required (no tap without it when the employer requires it) | App functionality; Fraud prevention, security and compliance | Front camera only, ≤ 640 px JPEG (`photo_compressor.dart`). On the phone the image is deleted from the queue row once the tap is sent, refused or discarded (`sqlite_tap_store.dart` `_finish`, `rejectWaitingNotOwnedBy`). |
| Personal info → **User IDs** | Yes (Employee ID typed at login; employee record id returned by the server and stored with queued taps) | No | No | Required | App functionality; Account management | `api_models.dart` `Employee`, `session_store.dart` |
| Device or other IDs | Yes: `ANDROID_ID` (`hardware_id`), app-install UUID (`device.id`), phone's local IP (`device.local_ip`); ML Kit per-installation identifiers (collected by Google) | No | No | Required | App functionality; Fraud prevention, security and compliance (device binding); Analytics (ML Kit only) | `hardware_id.dart`, `system_channel.dart` (`getAndroidId`), `local_ip.dart`. Play has no separate "IP address" type; declaring the local IP here is the conservative choice (**confirm**). |
| App info and performance → **Diagnostics** | Yes, by Google ML Kit (performance metrics, error codes, API configuration, event type) | No (Google: ML Kit "does not transfer this data to third-parties") | No | Required (no opt-out in the app) | Analytics | Google: "Used for diagnostics and usage analytics". https://developers.google.com/ml-kit/android-data-disclosure |
| App activity → **App interactions** | Yes, by Google ML Kit ("usage analytics": API usage events) | No | No | Required | Analytics | Conservative reading of Google's "usage analytics" (**confirm**). |
| App activity → **Other actions** | Yes: each attendance tap (card UID, tap time, check-in/out action, offline flag) | No | No | Required | App functionality | `punch_body.dart`. Could also be argued as not a "user activity" type; declaring it is the safe side (**confirm**). |
| Personal info → Name | **No** (the app does not send a name; it only displays the name the employer entered, received from the server) | – | – | – | – | Name is collected by the employer's portal, not by the app. |
| Personal info → Email, phone, address, other | No | – | – | – | – | |
| Financial, health, messages, audio, files, calendar, contacts, web history, installed apps | No | – | – | – | – | The app never reads these. |

## Apple: App Privacy

"Tracking": **No** for every type (no advertising, no data brokers, no IDFA; the app does not link
data with other companies' data for advertising).

| Apple category → type | Collected | Linked to the user | Used for tracking | Purposes | Notes |
|---|---|---|---|---|---|
| Location → **Precise Location** | Yes | Yes | No | App Functionality | When-in-use only (`NSLocationWhenInUseUsageDescription`; no Always key). |
| User Content → **Photos or Videos** | Yes (when the employer requires photos) | Yes | No | App Functionality | Taken with the in-app camera; not from the photo library. |
| Identifiers → **User ID** | Yes (Employee ID, employee record id) | Yes | No | App Functionality | |
| Identifiers → **Device ID** | Yes (`identifierForVendor`, app-install UUID) | Yes | No | App Functionality (Apple's definition includes fraud prevention and security) | `hardware_id.dart` (`iosVendorId`, cached in the Keychain). |
| Diagnostics → **Performance Data** / **Other Diagnostic Data** | Yes, by Google ML Kit | No | No | Analytics | Google (iOS): "Per-installation identifiers that are not intended to uniquely identify a user or physical device"; "Used for diagnostics and usage analytics". https://developers.google.com/ml-kit/ios-data-disclosure. On iPhone only face detection uses ML Kit (QR codes use Apple Vision). |
| Usage Data → **Product Interaction** | Yes, by Google ML Kit (usage analytics) | No | No | Analytics | Conservative reading (**confirm**). |
| Other Data → **Other Data Types** | Yes: local IP address, card UID, tap time, mock-location flag, phone model, OS and app version | Yes | No | App Functionality | |
| Contact Info → Name | No | – | – | – | Displayed only, not sent by the app. |
| Sensitive Info (biometric) | **No** | – | – | – | Face *detection* only, on the phone; no face template or biometric identifier is created or sent (`mlkit_face_finder.dart`, `face_quality.dart`). Only `photo.faces` (always 1) goes with the photo. |

## Open points before submitting

1. **Microphone and storage permissions in the APK.** `camera_android_camerax` 0.7.6+1 declares
   `RECORD_AUDIO` and `WRITE_EXTERNAL_STORAGE` (maxSdk 28); the merged release manifest also has
   `READ_EXTERNAL_STORAGE`. The app never requests them (`enableAudio: false`), but Play lists them on
   the store page. To drop them, add to `android/app/src/main/AndroidManifest.xml` (with
   `xmlns:tools="http://schemas.android.com/tools"` on `<manifest>`):
   `<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />` and the
   same for the two storage permissions. Not done here (owner decision; needs an on-device camera check).
2. **iOS privacy manifest.** `ios/Runner` has no `PrivacyInfo.xcprivacy`. The plugins ship their own,
   but check App Store Connect's warnings on the first upload.
3. **ML Kit wording.** The table follows Google's pages as of 2026-11-22; Google does not map ML Kit to
   Play or Apple categories itself. The "App interactions" / "Product Interaction" rows are a
   conservative choice.
4. **Public IP.** Recorded by the server, never sent by the app; most guidance does not require
   declaring server-observed IPs, but the privacy policy states it.
