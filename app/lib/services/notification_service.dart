/// Local + remote notification glue.
///
/// Owns the FCM topic subscription state for the three Pro topics (`all`,
/// `security`, `releases`) — preferences live in [SharedPreferences] under
/// the `notif_*` keys; the actual subscribe/unsubscribe only fires when the
/// user holds the Pro entitlement.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FCM topics gated behind Pro. Order matters for [topicPrefKeys].
const List<String> kProNotificationTopics = ['all', 'security', 'releases'];

/// SharedPreferences key for the per-topic on/off pref. Defaults to true on
/// first launch — see [getTopicEnabled].
String topicPrefKey(String topic) => 'notif_$topic';

class NotificationService {
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channel = AndroidNotificationChannel(
    'shiftfeed_alerts',
    'ShiftFeed Alerts',
    description: 'CVE and release alerts from ShiftFeed',
    importance: Importance.high,
  );

  /// One-time setup of the local notification channel + foreground handler.
  static Future<void> initialize() async {
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    // Permission is already requested by FirebaseMessaging in main(); asking
    // again here would put a second prompt path in front of the user.
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );
    await _localNotifications.initialize(initSettings);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;

      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            color: const Color(0xFFEE0000),
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    });
  }

  /// Returns the saved enabled-state for [topic], defaulting to true if the
  /// pref has never been written.
  static Future<bool> getTopicEnabled(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(topicPrefKey(topic)) ?? true;
  }

  /// Persists the enabled-state for [topic] and immediately reconciles the
  /// FCM subscription if [isPro] is true.
  ///
  /// When [isPro] is false the pref is still written but no FCM call is made
  /// — the user can toggle freely while the gate holds.
  static Future<void> setTopicEnabled(
    String topic, {
    required bool enabled,
    required bool isPro,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(topicPrefKey(topic), enabled);
    if (!isPro) return;
    final messaging = FirebaseMessaging.instance;
    if (enabled) {
      await messaging.subscribeToTopic(topic);
    } else {
      await messaging.unsubscribeFromTopic(topic);
    }
  }

  /// Reconciles every Pro topic's FCM subscription against the saved prefs.
  ///
  /// When [isPro] is false this unsubscribes from every topic — required so
  /// users who let their trial lapse stop receiving pushes.
  static Future<void> applyTopicSubscriptions({required bool isPro}) async {
    final messaging = FirebaseMessaging.instance;
    for (final topic in kProNotificationTopics) {
      if (!isPro) {
        await messaging.unsubscribeFromTopic(topic);
        continue;
      }
      final enabled = await getTopicEnabled(topic);
      if (enabled) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    }
  }
}
