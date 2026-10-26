import 'package:url_launcher/url_launcher.dart';

const termsUrl = 'https://pingduck.app/terms';
const privacyUrl = 'https://pingduck.app/privacy';
const websiteUrl = 'https://pingduck.app';
const playStoreUrl = 'https://play.google.com/store/apps/details?id=app.webcap.pingduck';
const playStoreMarketUrl = 'market://details?id=app.webcap.pingduck';

/// Opens the app page in Google Play Store.
Future<bool> openPlayStore() async {
  if (await openExternalUrl(playStoreMarketUrl)) return true;
  return openExternalUrl(playStoreUrl);
}

/// Opens [url] outside the app: the browser, or Google Play for its
/// subscription page. False when nothing could open it.
Future<bool> openExternalUrl(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
