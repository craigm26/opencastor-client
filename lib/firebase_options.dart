// ⚠️  Real credentials — do NOT commit this file with real values.
//
// The CI workflow injects the full file from the FIREBASE_OPTIONS_DART secret.
// This local copy is used for manual builds on the Pi only.
//
// To regenerate:
//   flutterfire configure --project=opencastor --platforms=web,android,ios

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
    apiKey: 'AIzaSyBKu6FelY5d4RwKPPO_MwapXO-wklHCFbE',
    appId: '1:360358330839:web:f35773ab2c6a78092c0b92',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    authDomain: 'opencastor.firebaseapp.com',
    storageBucket: 'opencastor.firebasestorage.app',
    measurementId: 'G-2P14Z5H4NY',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDcFiuWRXADtoRzgRmKRoZsyv27I6xQrnY',
    appId: '1:360358330839:android:30060e51644ca3952c0b92',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
  );

  // iOS — add GoogleService-Info.plist for real values; using web key as fallback
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBKu6FelY5d4RwKPPO_MwapXO-wklHCFbE',
    appId: '1:360358330839:ios:a0edb9b7371b28622c0b92',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
    iosClientId: '360358330839-08cfje1k0efm6c0kaj97kkmmfh4o1g94.apps.googleusercontent.com',
    iosBundleId: 'com.craigm26.opencastorClient',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBKu6FelY5d4RwKPPO_MwapXO-wklHCFbE',
    appId: '1:360358330839:ios:a0edb9b7371b28622c0b92',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
    iosClientId: '360358330839-08cfje1k0efm6c0kaj97kkmmfh4o1g94.apps.googleusercontent.com',
    iosBundleId: 'com.craigm26.opencastorClient',
  );
}
