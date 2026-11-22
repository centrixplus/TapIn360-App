/// TapIn360 master (company directory). Build-time constant:
/// `flutter build apk --dart-define=TAPIN_MASTER_URL=http://localhost:8051` for local testing.
const tapinMasterUrl = String.fromEnvironment(
  'TAPIN_MASTER_URL',
  defaultValue: 'https://tapin360-account.karrix.com',
);

/// `GET <master>/tapin/api/v1/company/<code>` (TapIn360 spec §5.6).
String directoryUrl(String masterUrl, String code) =>
    '${masterUrl.replaceFirst(RegExp(r'/+$'), '')}/tapin/api/v1/company/${Uri.encodeComponent(code)}';
