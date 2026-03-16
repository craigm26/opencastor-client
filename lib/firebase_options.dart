// ⚠️  This is a BUILD PLACEHOLDER — do not use in production.
//
// Real values are stored as GitHub secret: FIREBASE_OPTIONS_DART
// The CI workflow injects the real file before building.
//
// To regenerate locally:
//   flutterfire configure --project=opencastor --platforms=web,android,ios
//   (requires Firebase CLI + flutterfire_cli + macOS for iOS)

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: 'PLACEHOLDER',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    authDomain: 'opencastor.firebaseapp.com',
    storageBucket: 'opencastor.firebasestorage.app',
    measurementId: 'G-2P14Z5H4NY',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: 'PLACEHOLDER',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: 'PLACEHOLDER',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
    iosClientId: 'PLACEHOLDER',
    iosBundleId: 'com.craigm26.opencastorClient',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'PLACEHOLDER',
    appId: 'PLACEHOLDER',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
    iosClientId: 'PLACEHOLDER',
    iosBundleId: 'com.craigm26.opencastorClient',
  );
}
