import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'ua_detector_stub.dart'
    if (dart.library.js_interop) 'ua_detector_web.dart';
import '../../core/app_logger.dart';

/// Centralises all authentication logic.
///
/// Web auth strategy (per Firebase docs + flutter/web constraints):
///   1. iOS Safari: skip signInWithPopup entirely — Flutter web canvas apps
///      cannot reliably propagate user gestures to the window level on
///      iPhone/iPad, so popups fail silently. Go straight to redirect.
///   2. Other browsers: Use signInWithPopup — this is the documented primary
///      method. Firebase handles the entire flow on opencastor.firebaseapp.com,
///      so no cross-origin storage issues.
///   3. The Cloudflare Pages _headers file sets:
///         Cross-Origin-Opener-Policy: same-origin-allow-popups
///      which allows the popup to post the auth result back to the opener.
///   4. Fallback to signInWithRedirect for browsers that block popups or
///      return a popup-related FirebaseAuthException. getRedirectResult()
///      in main() catches the result on return.
///
/// Why not redirect-first (non-iOS):
///   signInWithRedirect stores pending state in IndexedDB on the authDomain
///   (opencastor.firebaseapp.com). Modern browsers with strict privacy
///   settings block cross-origin storage access from app.opencastor.com,
///   so getRedirectResult() silently returns null and the user loops back
///   to /login.
///
/// google_sign_in v7 migration notes (see PR #82):
///   - `GoogleSignIn()` constructor removed — use `GoogleSignIn.instance` singleton.
///   - Must call `initialize()` before any other method.
///   - Authentication (identity) and authorization (API scopes) are now separate.
///     Firebase sign-in uses `account.authentication.idToken` only.
///     `accessToken` was removed from `GoogleSignInAuthentication` in v7;
///     use `authorizationClient.authorizationForScopes()` for additional scopes.
class AuthService {
  const AuthService._();

  static final _googleProvider = GoogleAuthProvider()
    ..addScope('email')
    ..addScope('profile');

  /// Initialize GoogleSignIn. Must be called once before [signInWithGoogle]
  /// on native platforms. Safe to call multiple times (no-op after first call).
  ///
  /// On web, Firebase handles auth directly — GoogleSignIn.initialize() is
  /// not required.
  static Future<void> initializeGoogleSignIn() async {
    if (kIsWeb) return;
    try {
      await GoogleSignIn.instance.initialize();
      log.d('AuthService: GoogleSignIn.instance.initialize() complete');
    } catch (e) {
      log.w('AuthService: GoogleSignIn.initialize() failed (non-fatal): $e');
    }
  }

  /// Initiate Google sign-in.
  ///
  /// Web: iOS Safari → signInWithRedirect directly.
  ///      Other browsers → signInWithPopup (primary) → signInWithRedirect
  ///      fallback for any popup-related FirebaseAuthException.
  /// Native: GoogleSignIn plugin → Firebase credential.
  static Future<void> signInWithGoogle() async {
    log.i('AuthService: signInWithGoogle() — isWeb=$kIsWeb');
    if (kIsWeb) {
      // iOS Safari cannot reliably open popups from Flutter web canvas apps —
      // the canvas rendering model doesn't propagate user gestures to the
      // window level. Skip signInWithPopup and go straight to redirect.
      if (isMobileSafari()) {
        log.i(
          'AuthService: iOS Safari detected — using signInWithRedirect directly',
        );
        await FirebaseAuth.instance.signInWithRedirect(_googleProvider);
        return;
      }

      // Error codes where popup failed for environmental reasons — fall back
      // to redirect rather than surfacing an error to the user.
      const popupFallbackCodes = {
        'popup-blocked',
        'cancelled-popup-request',
        'web-context-cancelled',
        'operation-not-supported-in-this-environment',
        'web-storage-unsupported',
      };

      try {
        final cred =
            await FirebaseAuth.instance.signInWithPopup(_googleProvider);
        log.i(
          'AuthService: popup sign-in OK — uid=${cred.user?.uid} email=${cred.user?.email}',
        );
        return;
      } on FirebaseAuthException catch (e) {
        if (popupFallbackCodes.contains(e.code)) {
          log.w(
            'AuthService: popup failed (${e.code}), falling back to redirect',
          );
          await FirebaseAuth.instance.signInWithRedirect(_googleProvider);
        } else {
          log.e('AuthService: signInWithPopup error', error: e);
          rethrow;
        }
      }
      return;
    }

    // Native mobile / desktop: GoogleSignIn v7 plugin → Firebase credential.
    // v7: authenticate() throws GoogleSignInException(code: canceled) when the
    // user dismisses the picker — it never returns null. Catch that and return
    // silently; all other exceptions propagate.
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        log.d('AuthService: Google sign-in cancelled by user');
        return;
      }
      rethrow;
    }

    // Obtain Firebase-compatible tokens via account.authentication.
    // In google_sign_in v7, GoogleSignInAuthentication only exposes:
    //   - idToken: proves identity to Firebase (required for signInWithCredential)
    //   - serverAuthCode: for server-side token exchange (not needed here)
    // accessToken is no longer on GoogleSignInAuthentication in v7;
    // use account.authorizationClient.authorizationForScopes() if additional
    // OAuth scopes are needed (separate from Firebase sign-in).
    final authentication = await account.authentication;
    final cred = GoogleAuthProvider.credential(
      idToken: authentication.idToken,
    );
    await FirebaseAuth.instance.signInWithCredential(cred);
    log.i(
      'AuthService: native sign-in OK — uid=${FirebaseAuth.instance.currentUser?.uid}',
    );
  }

  /// Call once at app startup to complete any pending redirect sign-in.
  ///
  /// Only relevant when signInWithRedirect was used as fallback.
  /// getRedirectResult() returns immediately if there is no pending redirect.
  static Future<void> handleRedirectResult() async {
    if (!kIsWeb) return;
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      if (result.user != null) {
        log.i(
          'AuthService: redirect sign-in completed — uid=${result.user!.uid} email=${result.user!.email}',
        );
      } else {
        log.d('AuthService: getRedirectResult — no pending redirect');
      }
    } on FirebaseAuthException catch (e) {
      log.w('AuthService: getRedirectResult error ${e.code}: ${e.message}');
    }
  }

  /// Sign out of Firebase (and Google on native).
  static Future<void> signOut() async {
    if (!kIsWeb) {
      // v7: signOut via singleton
      await GoogleSignIn.instance.signOut();
    }
    await FirebaseAuth.instance.signOut();
  }

  /// Live stream of the current [User] (null when signed out).
  static Stream<User?> get authStateChanges =>
      FirebaseAuth.instance.authStateChanges();

  /// The currently authenticated user, or null.
  static User? get currentUser => FirebaseAuth.instance.currentUser;
}
