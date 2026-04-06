import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Handles FCM push token registration and foreground message routing.
class NotificationService {
  final FirebaseMessaging _msg;
  final FirebaseFunctions _fn;

  NotificationService({FirebaseMessaging? msg, FirebaseFunctions? fn})
      : _msg = msg ?? FirebaseMessaging.instance,
        _fn = fn ?? FirebaseFunctions.instance;

  /// Call once at login. Requests permission and registers the FCM token.
  Future<void> init() async {
    // Request permission (iOS/web — Android grants by default)
    await _msg.requestPermission(alert: true, badge: true, sound: true);

    // getToken() can hang on iOS Simulator (no APNS) — never block app startup.
    String? token;
    try {
      token = await _msg.getToken().timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          debugPrint(
            'FCM getToken timed out (normal on iOS Simulator without push)',
          );
          return null;
        },
      );
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
    }
    if (token != null) {
      await _registerToken(token);
    }

    // Refresh token when it rotates
    _msg.onTokenRefresh.listen(_registerToken);

    // Foreground messages — handle in-app
    FirebaseMessaging.onMessage.listen(_handleForeground);
  }

  Future<void> _registerToken(String token) async {
    try {
      final callable = _fn.httpsCallable('registerFcmToken');
      await callable.call({'token': token});
      debugPrint('FCM token registered');
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  void _handleForeground(RemoteMessage message) {
    final type = message.data['type'] as String?;
    debugPrint('FCM foreground: type=$type data=${message.data}');
    // Routing is handled by the app's notification stream (see providers)
  }

  /// Stream of incoming FCM messages while app is in foreground.
  Stream<RemoteMessage> get messageStream => FirebaseMessaging.onMessage;

  /// Stream of FCM messages that tapped the app open from background state.
  Stream<RemoteMessage> get tapStream => FirebaseMessaging.onMessageOpenedApp;

  /// Get the initial message if app was launched by tapping a notification.
  Future<RemoteMessage?> getInitialMessage() => _msg.getInitialMessage();
}
