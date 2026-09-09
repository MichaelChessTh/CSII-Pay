// File generated for Firebase initialization in CSII-Pay.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for CSII-Pay app.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDNSER_7QXid2enDxBZPadSsdFfQrsrM6s',
    appId: '1:796199113187:web:f031f1405a529cdb1910d6',
    messagingSenderId: '796199113187',
    projectId: 'csii-pay',
    authDomain: 'csii-pay.firebaseapp.com',
    storageBucket: 'csii-pay.firebasestorage.app',
    measurementId: 'G-QFLFSLVYF8',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD0Vf5aE18CdY47TBU-Gb-7U0SuY8qFemk',
    appId: '1:796199113187:android:a1f8e989ce1a82cd1910d6',
    messagingSenderId: '796199113187',
    projectId: 'csii-pay',
    storageBucket: 'csii-pay.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCJAaCwP77otTYK_g1TcbBAZIvL90Z2TYw',
    appId: '1:796199113187:ios:19b1124bc34c03bc1910d6',
    messagingSenderId: '796199113187',
    projectId: 'csii-pay',
    storageBucket: 'csii-pay.firebasestorage.app',
    iosBundleId: 'com.csiipay.csiiPayApp',
  );
}
