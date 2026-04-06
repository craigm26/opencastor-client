import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/app_logger.dart';
import 'web_user_agent.dart';

/// Centralises all authentication logic.
///
/// Web auth strategy:
///   iOS (WebKit) browsers use signInWithPopup. iOS Intelligent Tracking
///   Prevention (ITP) clears or blocks IndexedDB storage during the redirect
///   chain, so getRedirectResult() returns null on return — the user appears
///   signed out. Popups work fine on iOS since COOP does not block
///   window.close() in WebKit.
///
///   Desktop / non-iOS browsers use signInWithRedirect. COOP on Google's auth
///   servers blocks window.close() in the popup, causing Firebase to throw
///   auth/popup-closed-by-user. Since authDomain is app.opencastor.com
///   (same origin), the redirect is safe — no cross-origin IndexedDB issues.
///   getRedirectResult() in main() catches the result on return.
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

  /// True when running in a web browser on iOS (iPhone / iPad / iPod).
  /// Chrome iOS is WebKit under the hood — ITP breaks signInWithRedirect.
  static bool get _isIOSWeb {
    if (!kIsWeb) return false;
    return isIOSWebKitUserAgent();
  }

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
  /// Web: iOS (WebKit) → signInWithPopup (ITP breaks redirect storage).
  ///      Desktop/other → signInWithRedirect (COOP blocks popup window.close).
  /// Native: GoogleSignIn plugin → Firebase credential.
  static Future<void> signInWithGoogle() async {
    log.i('AuthService: signInWithGoogle() — isWeb=$kIsWeb');
    if (kIsWeb) {
      if (_isIOSWeb) {
        // iOS WebKit: ITP blocks IndexedDB across redirect — use popup instead.
        log.i('AuthService: iOS web — using signInWithPopup');
        await FirebaseAuth.instance.signInWithPopup(_googleProvider);
      } else {
        // Desktop/other: COOP blocks popup window.close() — use redirect.
        log.i('AuthService: web — using signInWithRedirect');
        await FirebaseAuth.instance.signInWithRedirect(_googleProvider);
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
