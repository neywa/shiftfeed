/// Wraps Supabase Auth. Provides the current session state and magic-link
/// sign-in. All other parts of the app use this service — never access
/// Supabase.instance.client.auth directly outside this file.
library;

import 'dart:async';

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

  /// Broadcast stream of human-readable error messages produced while
  /// processing a magic-link deep link. Surfaced separately from
  /// [authStateChanges] because Supabase's auth stream only emits on
  /// successful state transitions — failures (expired/used links, network
  /// timeouts) are otherwise silent. The AuthSheet listens to this stream
  /// to bring the user back to the email-entry stage with an explanation.
  final StreamController<String> _authErrorController =
      StreamController<String>.broadcast();
  Stream<String> get authErrors => _authErrorController.stream;

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
  ///
  /// The post-auth hydration calls (`linkUser`, `migrateLocalToCloud`,
  /// `registerToken`) are run independently with their own timeouts so a
  /// hang in one (e.g. a stuck RevenueCat platform channel) cannot block
  /// the others or leave the deep-link future unresolved indefinitely.
  Future<void> handleDeepLink(Uri uri) async {
    debugPrint('[Auth] handleDeepLink called: $uri');
    try {
      debugPrint('[Auth] calling getSessionFromUrl');
      await _auth
          .getSessionFromUrl(uri)
          .timeout(const Duration(seconds: 15));
      debugPrint('[Auth] session obtained, user: ${currentUser?.id}');
    } on TimeoutException {
      debugPrint('[Auth] getSessionFromUrl timed out');
      _authErrorController.add(
        'Sign-in is taking longer than expected. Check your connection '
        "and tap 'Send sign-in link' to try again.",
      );
      return;
    } on AuthException catch (e) {
      debugPrint('[Auth] getSessionFromUrl failed: ${e.code} ${e.message}');
      _authErrorController.add(_friendlyAuthMessage(e));
      return;
    } catch (e) {
      // Not an auth URI, or some other parser failure — ignore silently
      // since this same channel may carry non-auth deep links in future.
      debugPrint('[Auth] getSessionFromUrl failed: $e');
      return;
    }

    final uid = currentUser?.id;
    if (uid == null) {
      debugPrint('[Auth] no uid after getSessionFromUrl, skipping post-auth');
      return;
    }

    // Best-effort hydration. Each call is independent: failures and
    // timeouts are logged but never block subsequent calls.
    await _runStage(
      'linkUser',
      () => EntitlementService.instance.linkUser(uid),
    );
    await _runStage(
      'migrateLocalToCloud',
      () => BookmarkService.instance.migrateLocalToCloud(),
    );
    await _runStage(
      'registerToken',
      () => DeviceTokenService.instance.registerToken(),
    );
    debugPrint('[Auth] handleDeepLink complete');
  }

  Future<void> _runStage(String name, Future<void> Function() body) async {
    debugPrint('[Auth] calling $name');
    try {
      await body().timeout(const Duration(seconds: 10));
      debugPrint('[Auth] $name ok');
    } on TimeoutException {
      debugPrint('[Auth] $name timed out');
    } catch (e) {
      debugPrint('[Auth] $name failed: $e');
    }
  }

  String _friendlyAuthMessage(AuthException e) {
    // PKCE codes are single-use. Re-clicking an old or already-consumed
    // link gets a 404 with code=flow_state_not_found from Supabase.
    if (e.code == 'flow_state_not_found') {
      return "This sign-in link has already been used or expired. "
          "Tap 'Send sign-in link' below to get a fresh one.";
    }
    final lower = e.message.toLowerCase();
    if (lower.contains('expired')) {
      return 'This sign-in link has expired. Please request a new one.';
    }
    return 'Sign-in failed: ${e.message}';
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
