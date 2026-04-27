import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await NotificationService.instance.showLocalNotification(
    title: message.notification?.title ?? 'Expiry Alert',
    body: message.notification?.body ?? '',
    payload: message.data['productId'],
  );
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _fcm = FirebaseMessaging.instance;
  final _localNotifs = FlutterLocalNotificationsPlugin();

  static const _channelId = 'expiry_alerts';
  static const _channelName = 'Expiry Alerts';
  static const _channelDesc = 'Alerts for products expiring soon';

  // ─── Initialization ───────────────────────────────────────────────────────

  Future<void> initialize(BuildContext context) async {
    await _requestPermissions();
    await _setupLocalNotifications();
    _setupForegroundHandler();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _handleNotificationTap();
  }

  Future<void> _requestPermissions() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _setupLocalNotifications() async {
    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifs.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (details) {
        // Handle tap on local notification
        _onNotificationTap(details.payload);
      },
    );

    // Android notification channel
    await _localNotifs
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
  }

  void _setupForegroundHandler() {
    FirebaseMessaging.onMessage.listen((message) {
      showLocalNotification(
        title: message.notification?.title ?? 'Expiry Alert',
        body: message.notification?.body ?? '',
        payload: message.data['productId'],
      );
    });
  }

  void _handleNotificationTap() {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _onNotificationTap(message.data['productId']);
    });
  }

  void _onNotificationTap(String? productId) {
    // Navigate to dashboard — handled via navigatorKey in main.dart
    if (productId != null) {
      navigatorKey.currentState?.pushNamed('/dashboard', arguments: productId);
    } else {
      navigatorKey.currentState?.pushNamed('/dashboard');
    }
  }

  // ─── Show notification ────────────────────────────────────────────────────

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    await _localNotifs.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ─── FCM Token ────────────────────────────────────────────────────────────

  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  // Navigator key for navigation from notification tap
  static final navigatorKey = GlobalKey<NavigatorState>();
}