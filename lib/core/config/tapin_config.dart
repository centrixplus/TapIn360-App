/// TapIn360 master (company directory). Build-time constant:
/// `flutter build apk --dart-define=TAPIN_MASTER_URL=http://localhost:8051` for local testing.
const tapinMasterUrl = String.fromEnvironment(
  'TAPIN_MASTER_URL',
  defaultValue: 'https://account.tapin360.co',
);

/// `GET <master>/tapin/api/v1/company/<code>` (TapIn360 spec §5.6).
String directoryUrl(String masterUrl, String code) =>
    '${masterUrl.replaceFirst(RegExp(r'/+$'), '')}/tapin/api/v1/company/${Uri.encodeComponent(code)}';

/// TapIn360 public website: the pages the stores require (Settings links).
const tapinWebsiteUrl = 'https://tapin360.co';

/// The website pages Settings opens in the browser, under `/<en|ar>/`.
enum WebsitePage {
  privacy('app/privacy'),
  support('support'),
  deleteAccount('delete-account');

  const WebsitePage(this.path);
  final String path;
}

/// `https://tapin360.co/ar/app/privacy`: the page in the app's language
/// (English for anything but Arabic).
Uri websitePageUrl(WebsitePage page, String languageCode) {
  final lang = languageCode == 'ar' ? 'ar' : 'en';
  return Uri.parse('$tapinWebsiteUrl/$lang/${page.path}');
}
