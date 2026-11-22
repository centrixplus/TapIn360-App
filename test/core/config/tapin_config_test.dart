import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_attendance/core/config/tapin_config.dart';

void main() {
  test('website pages are https://tapin360.co/<lang>/<page>', () {
    expect(websitePageUrl(WebsitePage.privacy, 'en').toString(), 'https://tapin360.co/en/app/privacy');
    expect(websitePageUrl(WebsitePage.support, 'ar').toString(), 'https://tapin360.co/ar/support');
    expect(websitePageUrl(WebsitePage.deleteAccount, 'ar').toString(), 'https://tapin360.co/ar/delete-account');
  });

  test('any language but Arabic gets the English page', () {
    expect(websitePageUrl(WebsitePage.privacy, 'fr').toString(), 'https://tapin360.co/en/app/privacy');
  });

  test('directory URL strips trailing slashes and encodes the code', () {
    expect(directoryUrl('https://account.tapin360.co/', 'acme'), 'https://account.tapin360.co/tapin/api/v1/company/acme');
  });
}
