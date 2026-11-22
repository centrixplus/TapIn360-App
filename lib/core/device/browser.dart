import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the phone's browser, outside the app. False when nothing
/// could open it (no browser, or the platform refused).
Future<bool> openInBrowser(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
