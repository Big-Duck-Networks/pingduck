import 'package:url_launcher/url_launcher.dart';

const termsUrl = 'https://pingduck.app/terms';
const privacyUrl = 'https://pingduck.app/privacy';

/// Opens [url] outside the app: the browser, or Google Play for its
/// subscription page. False when nothing could open it.
Future<bool> openExternalUrl(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
