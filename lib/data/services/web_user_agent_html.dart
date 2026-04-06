import 'package:web/web.dart' as web;

/// True for iPhone / iPad / iPod browsers (WebKit + ITP affects redirect auth).
bool isIOSWebKitUserAgent() {
  final ua = web.window.navigator.userAgent.toLowerCase();
  return ua.contains('iphone') ||
      ua.contains('ipad') ||
      ua.contains('ipod');
}
