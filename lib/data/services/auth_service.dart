import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Centralises all authentication logic.
///
/// Auth state is exposed via [authStateChanges] which the router (go_router)
/// and [authStateProvider] listen to for redirects.
///
/// Web note: signInWithRedirect is used instead of signInWithPopup because
/// Cloudflare Pages sets Cross-Origin-Opener-Policy: same-origin, which
/// blocks the window.closed polling that signInWithPopup relies on.
class AuthService {
  const AuthService._();

  /// Initiate Google sign-in.
  ///
  /// - Web: full-page redirect via [FirebaseAuth.signInWithRedirect].
  ///   Call [handleRedirectResult] on app startup to complete.
  /// - Native: [GoogleSignIn] popup → Firebase credential.
  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');
      await FirebaseAuth.instance.signInWithRedirect(provider);
      return;
    }

    final gs = GoogleSignIn();
    final account = await gs.signIn();
    if (account == null) return; // user cancelled
    final auth = await account.authentication;
    final cred = GoogleAuthProvider.credential(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
    );
    await FirebaseAuth.instance.signInWithCredential(cred);
  }

  /// Must be called once in [main] to complete any pending web redirect flow.
  static Future<void> handleRedirectResult() async {
    if (!kIsWeb) return;
    try {
      final result = await FirebaseAuth.instance.getRedirectResult();
      if (result.user != null) {
        debugPrint('AuthService: redirect sign-in completed — ${result.user!.email}');
      }
    } catch (e) {
      debugPrint('AuthService: getRedirectResult error: $e');
    }
  }

  /// Sign out of Firebase (and Google on native).
  static Future<void> signOut() async {
    if (!kIsWeb) {
      // On web, auth was via signInWithRedirect — no GoogleSignIn session.
      await GoogleSignIn().signOut();
    }
    await FirebaseAuth.instance.signOut();
  }

  /// Live stream of the current [User] (null when signed out).
  static Stream<User?> get authStateChanges =>
      FirebaseAuth.instance.authStateChanges();

  /// The currently authenticated user, or null.
  static User? get currentUser => FirebaseAuth.instance.currentUser;
}
