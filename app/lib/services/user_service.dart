/// Wraps Supabase Auth. Provides the current session state and magic-link
/// sign-in. All other parts of the app use this service — never access
/// Supabase.instance.client.auth directly outside this file.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bookmark_service.dart';
import 'device_token_service.dart';
import 'entitlement_service.dart';

/// Deep-link redirect URL that Supabase sends magic-link emails to.
///
/// Must match the intent-filter scheme/host in
/// `android/app/src/main/AndroidManifest.xml` and `CFBundleURLSchemes` in
/// `ios/Runner/Info.plist`, and be registered in the Supabase dashboard
/// under Authentication > URL Configuration.
const String _kAuthRedirectUrl = 'shiftfeed://auth-callback';

class UserService {
  UserService._();
  static final UserService _instance = UserService._();
  static UserService get instance => _instance;

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// The current Supabase user, or null if no session is active.
  User? get currentUser => _auth.currentUser;

  /// Whether a Supabase user session currently exists.
  bool get isSignedIn => currentUser != null;

  /// Stream of [AuthState] events emitted by Supabase. Subscribe to react
  /// to sign-in/sign-out transitions.
  Stream<AuthState> get authStateChanges => _auth.onAuthStateChange;

  /// Sends a passwordless magic-link email to [email].
  ///
  /// On native platforms the email links back to [_kAuthRedirectUrl] which
  /// is intercepted by the deep-link handler in `main.dart`. On web the
  /// browser handles the redirect automatically.
  ///
  /// Throws [AuthException] on failure — callers should display the
  /// `AuthException.message` to the user.
  Future<void> sendMagicLink(String email) async {
    await _auth.signInWithOtp(
      email: email,
      emailRedirectTo: kIsWeb ? null : _kAuthRedirectUrl,
    );
  }

  /// Completes a magic-link sign-in by exchanging the deep-link [uri] for
  /// a session.
  ///
  /// URIs that don't contain auth tokens are ignored silently — the same
  /// deep-link channel may carry non-auth URIs in the future.
  Future<void> handleDeepLink(Uri uri) async {
    try {
      await _auth.getSessionFromUrl(uri);
      final uid = currentUser?.id;
      if (uid != null) {
        await EntitlementService.instance.linkUser(uid);
        await BookmarkService.instance.migrateLocalToCloud();
        await DeviceTokenService.instance.registerToken();
      }
    } catch (_) {
      // Not an auth URI, or a stale token — ignore.
    }
  }

  /// Ends the current session locally and on Supabase, then unlinks the
  /// user from RevenueCat so the device reverts to an anonymous purchaser.
  Future<void> signOut() async {
    await _auth.signOut();
    await EntitlementService.instance.unlinkUser();
  }

  /// Re-establishes the RevenueCat ↔ Supabase link if a session is already
  /// present at app launch — call once during startup, after
  /// [EntitlementService.init].
  Future<void> init() async {
    final uid = currentUser?.id;
    if (uid != null) {
      await EntitlementService.instance.linkUser(uid);
    }
    // Initialise bookmark service after auth so it knows which backend to use
    await BookmarkService.instance.init();
    if (uid != null) {
      await BookmarkService.instance.migrateLocalToCloud();
      await DeviceTokenService.instance.registerToken();
    }
  }
}
