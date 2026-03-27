// dart:html is deprecated in favour of package:web + dart:js_interop.
// Suppressed here because: (a) this file only compiles on Flutter web targets
// via the conditional export in sw_updater.dart, and (b) package:web is not
// yet a declared dependency. Migrate when upgrading Flutter ≥ 3.29 + web ^1.0.
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Asks the browser to check for a service-worker update.
///
/// The browser downloads the new SW in the background and activates it on
/// the next page load — no disruption to the current session.
/// All errors are caught and silently dropped (always best-effort).
void triggerSwUpdate() {
  try {
    html.window.navigator.serviceWorker
        ?.getRegistrations()
        .then((regs) {
          for (final reg in regs) {
            reg.update().catchError((_) {});
          }
        })
        .catchError((_) {});
  } catch (_) {
    // JS interop failure or SW API unavailable — ignore silently.
  }
}
