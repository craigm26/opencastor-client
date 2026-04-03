// Firebase Cloud Messaging Service Worker
// Required for web push notifications (firebase_messaging Flutter package).
// Must be served at the root: /firebase-messaging-sw.js
//
// NOTE: Firebase web API keys are PUBLIC by design — they identify the project,
// not authenticate admin operations. Security is enforced by Firestore rules +
// Firebase Auth, not by keeping this key secret. However, the real values are
// injected at build time by CI to keep git history clean.
//
// Placeholder values are replaced by the CI step "Write Firebase credentials"
// using the FIREBASE_SW_CONFIG GitHub Secret.

importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "%%FIREBASE_API_KEY%%",
  authDomain: "app.opencastor.com",
  projectId: "opencastor",
  storageBucket: "opencastor.firebasestorage.app",
  messagingSenderId: "360358330839",
  appId: "%%FIREBASE_APP_ID%%",
  measurementId: "G-2P14Z5H4NY"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log("[firebase-messaging-sw.js] Background message:", payload);
  const title = payload.notification?.title ?? "OpenCastor Alert";
  const options = {
    body: payload.notification?.body ?? "",
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
    data: payload.data,
  };
  self.registration.showNotification(title, options);
});
