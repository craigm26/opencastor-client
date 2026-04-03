// Service-worker update helper — conditional import shim.
//
// On web: calls `navigator.serviceWorker.getRegistrations().update()` so
// the browser checks for a fresh SW on every app start. This prevents stale
// SWs from surviving across Cloudflare Pages deploys.
//
// On non-web (Android, iOS, macOS …): no-op. The conditional export ensures
// dart:html is never imported in non-web builds (which would fail to compile).
export 'sw_updater_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) 'sw_updater_web.dart';
