import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/app_logger.dart';

/// Centralises all authentication logic.
///
/// Web auth strategy (per Firebase docs + flutter/web constraints):
///   1. Use signInWithPopup — this is the documented primary method.
///      Firebase handles the entire flow on opencastor.firebaseapp.com,
///      so no cross-origin storage issues.
///   2. The Cloudflare Pages _headers file sets:
///         Cross-Origin-Opener-Policy: same-origin-allow-popups
///      which allows the popup to post the auth result back to the opener.
///   3. Fallback to signInWithRedirect ONLY for browsers that block all
///      popups (popup-blocked, cancelled-popup-request). getRedirectResult()
///      in main() catches the result on return.
///
/// Why not redirect-first:
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
///     Firebase sign-in uses `account.authentication` for idToken + accessToken.
///     `authorizationClient.authorizationForScopes()` is only for additional
///     OAuth scopes beyond basic sign-in — it does NOT return an idToken.
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
  /// Web: signInWithPopup (primary) → signInWithRedirect (popup-blocked fallback).
  /// Native: GoogleSignIn plugin → Firebase credential.
  static Future<void> signInWithGoogle() async {
    log.i('AuthService: signInWithGoogle() — isWeb=$kIsWeb');
    if (kIsWeb) {
      try {
        final cred =
            await FirebaseAuth.instance.signInWithPopup(_googleProvider);
        log.i(
          'AuthService: popup sign-in OK — uid=${cred.user?.uid} email=${cred.user?.email}',
        );
        return;
      } on FirebaseAuthException catch (e) {
        // Only fall back to redirect if the popup was truly blocked by the
        // browser's popup blocker — not for COOP or auth errors.
        if (e.code == 'popup-blocked' || e.code == 'cancelled-popup-request') {
          log.w(
            'AuthService: popup blocked (${e.code}), falling back to redirect',
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
    // v7: use singleton; authenticate() returns the signed-in account.
    final account = await GoogleSignIn.instance.authenticate();
    if (account == null) return; // user cancelled

    // Obtain Firebase-compatible tokens via account.authentication.
    // - idToken: proves identity to Firebase (required)
    // - accessToken: grants API access (optional but included for parity)
    // Note: authorizationClient.authorizationForScopes() returns only an
    // access token for additional scopes — it does NOT return an idToken
    // and should NOT be used for Firebase sign-in.
    final authentication = await account.authentication;
    final cred = GoogleAuthProvider.credential(
      idToken: authentication.idToken,
      accessToken: authentication.accessToken,
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
