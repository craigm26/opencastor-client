import 'package:web/web.dart' as web;

/// Returns true if running on iPhone or iPad Safari.
bool isMobileSafari() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') || ua.contains('ipad');
}
