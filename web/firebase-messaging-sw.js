// Firebase Cloud Messaging Service Worker
// Required for web push notifications (firebase_messaging Flutter package).
// Must be served at the root: /firebase-messaging-sw.js
//
// This file registers the FCM background message handler.
// The Firebase config here uses PUBLIC web credentials (apiKey is NOT secret
// for web apps — security is enforced by Firestore rules + Firebase Auth).

importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyBKu6FelY5d4RwKPPO_MwapXO-wklHCFbE",
  authDomain: "opencastor.firebaseapp.com",
  projectId: "opencastor",
  storageBucket: "opencastor.firebasestorage.app",
  messagingSenderId: "360358330839",
  appId: "1:360358330839:web:f35773ab2c6a78092c0b92",
  measurementId: "G-2P14Z5H4NY"
});

const messaging = firebase.messaging();

// Handle background push messages (app not in foreground)
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
