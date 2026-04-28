/// Registers and refreshes the FCM device token for the signed-in user
/// in the `user_device_tokens` Supabase table, enabling the scraper to
/// send targeted push notifications for custom alert rules.
///
/// Web is unsupported (no FCM); the methods are no-ops there.
library;

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_service.dart';

const String _kTable = 'user_device_tokens';

class DeviceTokenService {
  DeviceTokenService._();
  static final DeviceTokenService _instance = DeviceTokenService._();
  static DeviceTokenService get instance => _instance;

  /// Retrieves the current FCM token from FirebaseMessaging and upserts
  /// it into `user_device_tokens` for the signed-in user.
  ///
  /// No-op on web, when not signed in, or on non-mobile platforms.
  /// Safe to call multiple times — the upsert is idempotent on
  /// `(user_id, fcm_token)`.
  Future<void> registerToken() async {
    if (kIsWeb) return;
    if (!UserService.instance.isSignedIn) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('[DeviceTokenService] FCM token unavailable, skipping.');
        return;
      }
      final platform = Platform.isAndroid ? 'android' : 'ios';
      await Supabase.instance.client.from(_kTable).upsert(
        {
          'user_id': UserService.instance.currentUser!.id,
          'fcm_token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,fcm_token',
      );
    } catch (e) {
      debugPrint('[DeviceTokenService] registerToken failed: $e');
    }
  }

  /// Subscribes to FCM's [FirebaseMessaging.onTokenRefresh] and re-runs
  /// [registerToken] whenever a new token is issued. Call once during
  /// startup.
  void listenForTokenRefresh() {
    if (kIsWeb) return;
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    FirebaseMessaging.instance.onTokenRefresh.listen((_) => registerToken());
  }
}
