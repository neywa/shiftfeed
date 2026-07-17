/// Local + remote notification glue.
///
/// Owns the FCM topic subscription state for every Pro topic — preferences
/// live in [SharedPreferences] under the `notif_*` keys; the actual
/// subscribe/unsubscribe only fires when the user holds the Pro entitlement.
library;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cve_severity.dart';

/// Per-severity CVE topics, worst first. These strings are a contract with
/// the scraper's `SEVERITY_TOPICS` (scraper/sources/cve_severity.py) — it
/// publishes to exactly these names.
///
/// Derived from [CveSeverity] rather than written out, so the topics can
/// never drift from the buckets the CVE screen filters by.
final List<String> kCveTopics = [
  for (final s in CveSeverity.values) cveTopicFor(s),
];

/// The FCM topic carrying CVEs of [severity].
String cveTopicFor(CveSeverity severity) => 'cve_${severity.name}';

/// FCM topics gated behind Pro.
final List<String> kProNotificationTopics = ['all', 'releases', ...kCveTopics];

/// Topics we used to publish to and no longer do.
///
/// `security` carried every CVE regardless of severity; it is replaced by
/// the four [kCveTopics]. The scraper has stopped sending to it, but a
/// device that subscribed under the old build stays subscribed until it is
/// explicitly unsubscribed — so [applyTopicSubscriptions] unsubscribes from
/// everything here on EVERY launch, Pro or not. Unsubscribe is idempotent,
/// so this is self-healing: a device that is offline for the attempt gets
/// cleaned up on the next launch instead of being orphaned forever.
const List<String> kRetiredTopics = ['security'];

/// SharedPreferences key for the per-topic on/off pref.
String topicPrefKey(String topic) => 'notif_$topic';

/// First-launch default for [topic].
///
/// The CVE topics default OFF — a first-time Pro user opts into each
/// severity deliberately, rather than being opted in to four new streams by
/// an upgrade. `all` and `releases` keep their historical opt-OUT default so
/// this change doesn't silently mute existing subscribers.
bool defaultTopicEnabled(String topic) => !kCveTopics.contains(topic);

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

  /// Returns the saved enabled-state for [topic], falling back to
  /// [defaultTopicEnabled] if the pref has never been written.
  static Future<bool> getTopicEnabled(String topic) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(topicPrefKey(topic)) ?? defaultTopicEnabled(topic);
  }

  /// Waits for APNs to hand Firebase a device token, which happens some time
  /// after `requestPermission()` — not by the time startup code runs.
  ///
  /// Until that token lands, every FCM call on an Apple platform throws
  /// `[firebase_messaging/apns-token-not-set]`; that exception, awaited
  /// unguarded during startup, is what once left the app on a white screen.
  /// So every subscribe/unsubscribe/getToken call must pass through here.
  ///
  /// Returns true as soon as the token is available — and immediately on
  /// Android and web, which need no APNs token. Returns false if it never
  /// arrives within [timeout] (the iOS Simulator never issues one, and
  /// neither does a device whose user denied notifications), in which case
  /// callers must **skip** the FCM call rather than let it throw.
  static Future<bool> ensureApnsToken({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return true;
    }

    const pollInterval = Duration(milliseconds: 500);
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        if (await FirebaseMessaging.instance.getAPNSToken() != null) {
          return true;
        }
      } catch (e) {
        debugPrint('[NotificationService] getAPNSToken failed: $e');
      }
      if (!DateTime.now().isBefore(deadline)) {
        debugPrint('[NotificationService] APNs token unavailable after '
            '${timeout.inSeconds}s — skipping FCM topic subscriptions.');
        return false;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Persists the enabled-state for [topic] and immediately reconciles the
  /// FCM subscription if [isPro] is true.
  ///
  /// When [isPro] is false the pref is still written but no FCM call is made
  /// — the user can toggle freely while the gate holds. The pref is also
  /// written when the FCM call can't be made or fails, so a subscription
  /// missed here is picked up by [applyTopicSubscriptions] on next launch.
  static Future<void> setTopicEnabled(
    String topic, {
    required bool enabled,
    required bool isPro,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(topicPrefKey(topic), enabled);
    if (!isPro) return;
    if (!await ensureApnsToken()) return;

    try {
      // Resolved inside the try: this throws when Firebase failed to
      // initialise, which must not propagate out of a settings toggle —
      // the pref is already saved and next launch's reconcile will retry.
      final messaging = FirebaseMessaging.instance;
      if (enabled) {
        await messaging.subscribeToTopic(topic);
      } else {
        await messaging.unsubscribeFromTopic(topic);
      }
    } catch (e) {
      debugPrint('[NotificationService] $topic subscription failed: $e');
    }
  }

  /// The subscription state that SHOULD hold, given [isPro] and the saved
  /// prefs. Pure apart from reading SharedPreferences — no Firebase, which
  /// is what makes the reconcile rules testable without a live FCM.
  ///
  /// Retired topics come first and are always unsubscribed: a device
  /// subscribed to `security` under an older build would otherwise keep
  /// that subscription forever, and Pro state has no bearing on a topic
  /// nothing publishes to any more.
  ///
  /// When [isPro] is false every Pro topic resolves to unsubscribe —
  /// required so users who let their trial lapse stop receiving pushes.
  @visibleForTesting
  static Future<List<TopicAction>> planTopicSubscriptions({
    required bool isPro,
  }) async {
    final plan = <TopicAction>[
      for (final topic in kRetiredTopics)
        TopicAction(topic: topic, subscribe: false),
    ];
    for (final topic in kProNotificationTopics) {
      plan.add(
        TopicAction(
          topic: topic,
          subscribe: isPro && await getTopicEnabled(topic),
        ),
      );
    }
    return plan;
  }

  /// Reconciles every Pro topic's FCM subscription against the saved prefs,
  /// and unsubscribes from every [kRetiredTopics] entry.
  ///
  /// Never throws: a topic that fails is logged and the rest still
  /// reconcile. [FirebaseMessaging.instance] is resolved inside the try —
  /// it throws when Firebase failed to initialise, and that must not take
  /// down a settings toggle.
  static Future<void> applyTopicSubscriptions({required bool isPro}) async {
    if (!await ensureApnsToken()) return;

    for (final action in await planTopicSubscriptions(isPro: isPro)) {
      try {
        final messaging = FirebaseMessaging.instance;
        if (action.subscribe) {
          await messaging.subscribeToTopic(action.topic);
        } else {
          await messaging.unsubscribeFromTopic(action.topic);
        }
      } catch (e) {
        debugPrint('[NotificationService] ${action.topic} reconcile failed: $e');
      }
    }
  }
}

/// One reconcile step: subscribe to, or unsubscribe from, [topic].
@immutable
class TopicAction {
  final String topic;
  final bool subscribe;
  const TopicAction({required this.topic, required this.subscribe});

  @override
  bool operator ==(Object other) =>
      other is TopicAction &&
      other.topic == topic &&
      other.subscribe == subscribe;

  @override
  int get hashCode => Object.hash(topic, subscribe);

  @override
  String toString() => '${subscribe ? '+' : '-'}$topic';
}
