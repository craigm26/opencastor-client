// ⚠️  PLACEHOLDER — real values injected by CI from FIREBASE_OPTIONS_DART secret.
//
// DO NOT commit real API keys here. This file is .gitignored.
// To build locally: copy firebase_options.dart.example and fill in real values,
// OR run: flutterfire configure --project=opencastor --platforms=web,android,ios
//
// CI injects the real file via:
//   echo "$FIREBASE_OPTIONS_DART" > lib/firebase_options.dart

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
    authDomain: 'app.opencastor.com',
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

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBORI8TZ88k6-rFiEiV04j0KpVUDmmgF-I',
    appId: '1:360358330839:ios:66f6c2a7be80c1482c0b92',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
    iosClientId: '360358330839-c615jjves4lbk0ovrgel12ausvfa92bt.apps.googleusercontent.com',
    iosBundleId: 'com.craigm26.opencastorClient',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBORI8TZ88k6-rFiEiV04j0KpVUDmmgF-I',
    appId: '1:360358330839:ios:66f6c2a7be80c1482c0b92',
    messagingSenderId: '360358330839',
    projectId: 'opencastor',
    storageBucket: 'opencastor.firebasestorage.app',
    iosClientId: '360358330839-c615jjves4lbk0ovrgel12ausvfa92bt.apps.googleusercontent.com',
    iosBundleId: 'com.craigm26.opencastorClient',
  );
}
