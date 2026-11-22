# TapIn360 (Flutter, Android + iPhone)

TapIn360: employees open the app on their own phone and tap the NFC card fixed on the wall at the work site.
The app sends the card UID, a GPS fix and the tap time to a configurable server, which records a
check-in / check-out or rejects the tap with a reason.

- Design (source of truth): [`docs/superpowers/specs/2026-11-17-nfc-attendance-design.md`](docs/superpowers/specs/2026-11-17-nfc-attendance-design.md)
- Server contract for any backend: [`API.md`](API.md)
- Plans: [`docs/superpowers/plans/`](docs/superpowers/plans/)

- TapIn360 SaaS design (company directory, §7 app changes):
  `~/workspace/projects/projects20/TapIn/docs/superpowers/specs/2026-11-17-tapin-saas-design.md`

App ID: Android and iOS `com.centrixplus.tapin360`, name **TapIn360** (renamed from TapIn /
`com.centrixplus.tapin` on 2026-11-18). (The Dart package is still `nfc_attendance`; method channels
and the `TAPIN_MASTER_URL` define keep their names.) Phones with an older `com.centrixplus.tapin` or
`com.centrixplus.nfc_attendance` build keep it as a separate app. Cards are set up from the backend only (see Card setup); the app never writes to cards.

## First screen: company code

The app opens on **Your company**: the employee types the code from HR or scans the poster QR
(`tapin://company/<code>`). The app asks the TapIn360 master `GET <master>/tapin/api/v1/company/<code>`
and shows the company's name and logo; **Continue** stores its `api_base_url` and opens Login.
`active`/`grace` companies continue; `provisioning`/`suspended` show why not; unknown codes show
"We can't find that company code". **Use a custom server** keeps the manual Server URL setup for
on-premise or other servers. **Settings → Change** (company) logs out (unsent-taps confirmation).

The master is a build-time constant, default `https://account.tapin360.co`:

```bash
flutter run --dart-define=TAPIN_MASTER_URL=http://localhost:8051   # local master over adb reverse
```

## Run and test

Toolchain: Flutter 3.44.6 (`~/workspace/flutter/flutter/bin`).

```bash
export PATH=~/workspace/flutter/flutter/bin:$PATH
flutter pub get
flutter analyze          # expect: No issues found!
flutter test             # unit + widget tests (SQLite runs via sqflite_common_ffi on the host)
flutter run              # on a connected phone
```

### Against local servers over USB (Android)

```bash
adb reverse tcp:8046 tcp:8046   # attendance server (Odoo nfc_attendance)
adb reverse tcp:8051 tcp:8051   # TapIn360 master (company directory)
```

Company code lookup works against the local master (build with
`--dart-define=TAPIN_MASTER_URL=http://localhost:8051`); the phone cannot resolve
`<code>.localhost`, so local tenants must have an `api_base_url` on `localhost` (e.g.
`http://localhost:8052/nfc/api/v1`, or the dev proxy `http://localhost:8060/c/<code>/nfc/api/v1`).
**Use a custom server** → `http://localhost:8046/nfc/api/v1` also works.

Plain `http://` is allowed **only** for `localhost`, `127.0.0.1` and `10.0.2.2` (emulator), in debug
and release builds (Android `network_security_config.xml`, iOS `NSAllowsLocalNetworking`; no
`NSAllowsArbitraryLoads`). Every other server, including on-premise ones, must use `https://`: the
app refuses an `http://` Server URL or company `api_base_url` on any other host ("This server isn't
secure (https required)").

## Build

```bash
flutter build apk --debug                 # build/app/outputs/flutter-apk/app-debug.apk
flutter build apk --release               # signs with android/key.properties, else the debug key (warning)
```

Release signing (once, the keystore and passwords stay off git and are yours to keep safe):
1. `keytool -genkey -v -keystore ~/tapin360-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
2. Create `android/key.properties`: `storeFile=/home/<you>/tapin360-upload.jks`, `storePassword=…`, `keyAlias=upload`, `keyPassword=…`.
3. `flutter build apk --release` / `flutter build appbundle` now sign with it (no "DEBUG key" warning).
4. A phone with the debug-signed app must uninstall it first; the new key also changes `ANDROID_ID`, so HR approves the phone again.

iPhone (on the Mac with Xcode):

```bash
flutter build ios                          # or open ios/Runner.xcworkspace and Run
```

- Set your signing team in Xcode → Runner → Signing & Capabilities. `Runner/Runner.entitlements`
  already declares **NFC Tag Reading** (`com.apple.developer.nfc.readersession.formats` = `TAG`);
  the App ID needs that capability (automatic signing adds it).
- `flutter_secure_storage` 9.x has no Swift Package Manager support, so Flutter uses CocoaPods for
  it: CocoaPods must be installed on the Mac (`sudo gem install cocoapods` or Homebrew).
- iPhone 7 or newer, **iOS 15.5+** (Google ML Kit face detection). Info.plist has
  `NFCReaderUsageDescription`, `NSLocationWhenInUseUsageDescription` and `NSCameraUsageDescription`.
- `ios/Podfile` sets `platform :ios, '15.5'`; ML Kit is CocoaPods-only, so `pod install` runs on
  the first build. ML Kit does not run on the iOS Simulator on Apple-silicon Macs — test on an
  iPhone.

## Card setup per site (spec §9)

Cards are set up from the backend only; the app has no card-writing option.

1. **Get the card UID**: open TapIn360 and tap the new card. The server rejects it ("Card not
   registered") and logs the tap with its UID under Odoo → Attendances → NFC Taps (reject reason
   *unknown card*). The UID is the card's fixed factory ID.
2. **Register the card** on the server (Odoo → Attendances → Configuration → NFC Cards): the UID,
   the site's latitude/longitude and the radius (default 100 m).
3. Staff open TapIn360 first, then tap (Android reader mode; iPhone: **Scan card**). The card's own
   content (e.g. a website link) is ignored while the app is reading. Cards written earlier with our
   MIME record + Android Application Record still open the app when it is closed (the manifest
   filter is kept).
4. **At go-live**: NFC Tools → Other → **Set password** to block rewriting. Never use **Lock**
   (permanent).

## How a tap works

1. Home visible → GPS stream starts; on Android NFC reader mode is on (iPhone: press **Scan card**).
2. Same card within 10 s of the previous read → ignored (holding the card is one tap).
3. Location: latest fix if ≤ 30 s old, else wait up to 10 s; no fix → "No GPS signal — move near a
   window", nothing recorded.
4. The tap is stored as **Waiting**. If older taps are already waiting, it is queued behind them
   with `offline: true`, the result is "Saved — will send automatically" and the queue drains
   oldest-first — a new tap never overtakes waiting ones.
5. Otherwise it is sent at once with a 10 s timeout: 200 → **Sent** (green), 4xx → **Rejected**
   (red, server message, never retried), no answer / 5xx → stays Waiting ("Saved — will send
   automatically") and is resent with `offline: true`.
6. History shows the last 50 taps. Logging out with waiting taps asks to discard them.

## Design

TapIn360 design system (Karrix palette, IBM Plex Sans / Sans Arabic / Mono, radii 8/12/20, no
shadows): `lib/app/tokens.dart` + `lib/app/theme.dart`. Fonts are bundled in `assets/fonts`
(SIL Open Font License, `assets/fonts/OFL.txt`). App icon and splash use the NFC motif in white on
`#2563eb`; icon sources in `assets/branding` (`dart run flutter_launcher_icons` regenerates them).

Debug builds only: a **long-press on the NFC motif** on the tap screen acts as a card read (the
test card `04DB8FE23B1590`), so the camera and result screens can be checked without a card.

## Employee photo (spec §15)

When the server's `settings.photo_required` is on, each tap opens the in-app **front camera**
(no gallery): 3-second countdown with automatic capture, or the shutter button. ML Kit checks on
the phone, offline, that exactly one face is visible ("Face not visible — try again" / "Only you
should be in the photo"); **Cancel** discards the tap. GPS is taken while the camera is open and
`tapped_at` stays the card-read moment. The photo is resized to 640 px (JPEG quality ≈ 70,
typically 40–90 KB) and travels inside the punch, also when queued offline. Android asks for the
camera permission on the first photo.

## Device binding (spec §14)

Each login and tap sends the phone's **hardware ID** (Android `ANDROID_ID`, iOS
`identifierForVendor`; IMEI is not readable by normal apps) and each tap its local IPv4. A new
phone gets `403 device_not_allowed` until HR approves it; the Login screen then shows
**This phone's ID** (also in Settings) for HR to match. See `API.md` §9.

## Project layout

```
lib/
  app/        bootstrap, providers (Riverpod), router (go_router), theme
  core/
    api/      API contract v1 client (dio) + models + error codes
    config/   Server URL normalisation
    location/ GPS fix, freshness rules, geolocator gateway
    nfc/      UID formatting, card message, reader/writer, launch-tag channel
    device/   hardware ID, local IP, device block, Android system channel
    photo/    camera + face-counter interfaces (camera / ML Kit implementations), compressor
    queue/    SQLite tap store, oldest-first queue, retry triggers
    session/  session state + login/logout/401 handling
    storage/  secure key-value + session persistence
    tap/      debounce, auto/manual action, tap flow
    time/     ISO 8601 with offset
  features/   setup, login, home, photo (camera screen), result, history, settings
assets/translations/  en.json, ar.json
```
