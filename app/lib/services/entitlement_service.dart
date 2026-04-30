/// Thin wrapper around RevenueCat's [Purchases] SDK that exposes a single
/// `pro` entitlement check and surfaces purchase/restore errors as a sealed
/// [EntitlementException] hierarchy.
///
/// Web is unsupported — [init] is a no-op there and [isPro] always returns
/// false.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identifier of the single Pro entitlement configured in the RevenueCat
/// dashboard.
const String _kProEntitlementId = 'pro';

/// SharedPreferences key for the debug-only PRO override flag.
const String _kDevProOverridePref = 'dev_pro_override';

/// Thrown when [Purchases.purchasePackage] is cancelled by the user.
///
/// Distinct from generic errors so callers can dismiss the paywall silently
/// rather than show a SnackBar.
class UserCancelledPurchaseException implements Exception {
  const UserCancelledPurchaseException();
  @override
  String toString() => 'UserCancelledPurchaseException';
}

/// Sealed-style hierarchy of failures surfaced by [EntitlementService].
///
/// Subtypes intentionally don't carry stack traces — callers usually only
/// need the message for a SnackBar.
sealed class EntitlementException implements Exception {
  final String message;
  const EntitlementException(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

class EntitlementCancelledException extends EntitlementException {
  const EntitlementCancelledException()
      : super('Purchase was cancelled.');
}

class EntitlementNetworkException extends EntitlementException {
  const EntitlementNetworkException()
      : super('Network error — please check your connection.');
}

class EntitlementUnknownException extends EntitlementException {
  const EntitlementUnknownException(super.message);
}

class EntitlementService {
  EntitlementService._();
  static final EntitlementService _instance = EntitlementService._();
  static EntitlementService get instance => _instance;

  bool _initialized = false;

  /// Debug-only override that forces [isPro] to return true regardless
  /// of RevenueCat. Persisted via [SharedPreferences] so the toggle
  /// survives hot reload / cold start during local development.
  bool _devProOverride = false;
  bool _devProLoaded = false;

  bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Lazy-loads the dev override flag from SharedPreferences on first
  /// use. No-op outside debug builds — the flag is silently treated as
  /// false in release so a stray value from a prior debug install can
  /// never grant Pro in production.
  Future<void> _ensureDevProLoaded() async {
    if (_devProLoaded) return;
    if (!kDebugMode) {
      _devProLoaded = true;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _devProOverride = prefs.getBool(_kDevProOverridePref) ?? false;
    } catch (e) {
      debugPrint('[EntitlementService] dev override load failed: $e');
      _devProOverride = false;
    }
    _devProLoaded = true;
  }

  /// Toggles the debug-only PRO override and persists it. No-op in
  /// release builds. Returns the new value.
  Future<bool> toggleDevProOverride() async {
    if (!kDebugMode) return false;
    await _ensureDevProLoaded();
    _devProOverride = !_devProOverride;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDevProOverridePref, _devProOverride);
    } catch (e) {
      debugPrint('[EntitlementService] dev override persist failed: $e');
    }
    return _devProOverride;
  }

  /// Initialises RevenueCat with the given platform [apiKey].
  ///
  /// Safe to call multiple times — only the first call configures the SDK.
  /// No-op on web.
  Future<void> init(String apiKey) async {
    if (kIsWeb) return;
    if (_initialized) return;
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _initialized = true;
  }

  /// Returns true if the user currently has the `pro` entitlement active
  /// (covers both an active free trial and a paid subscription).
  ///
  /// In debug builds, the dev override (toggled via the long-press on
  /// the app title) short-circuits to true. Returns false on web or on
  /// any error querying RevenueCat — callers should treat false as
  /// "free tier" rather than "unknown".
  Future<bool> isPro() async {
    if (kDebugMode) {
      await _ensureDevProLoaded();
      if (_devProOverride) return true;
    }
    if (!_supported) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(_kProEntitlementId);
    } catch (_) {
      return false;
    }
  }

  /// Returns true if the user previously purchased something but no longer
  /// holds the `pro` entitlement — i.e. a trial or subscription that has
  /// expired.
  Future<bool> hasExpiredTrial() async {
    if (!_supported) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      final hasActivePro =
          info.entitlements.active.containsKey(_kProEntitlementId);
      if (hasActivePro) return false;
      return info.allPurchasedProductIdentifiers.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Fetches the current RevenueCat offerings, or null on web / failure.
  Future<Offerings?> getOfferings() async {
    if (!_supported) return null;
    try {
      return await Purchases.getOfferings();
    } catch (_) {
      return null;
    }
  }

  /// Purchases [package] and returns the resulting [CustomerInfo].
  ///
  /// Throws [UserCancelledPurchaseException] when the user cancels and
  /// [EntitlementException] for any other failure.
  Future<CustomerInfo> purchasePackage(Package package) async {
    try {
      return await Purchases.purchasePackage(package);
    } catch (e) {
      throw _mapPurchaseError(e);
    }
  }

  /// Links this device's RevenueCat anonymous ID to the authenticated
  /// Supabase user. Must be called after a successful Supabase sign-in.
  /// Safe to call multiple times — RC deduplicates.
  Future<void> linkUser(String userId) async {
    if (kIsWeb) return;
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('[EntitlementService] logIn failed: $e');
    }
  }

  /// Unlinks the user from RevenueCat on sign-out, reverting to anonymous.
  Future<void> unlinkUser() async {
    if (kIsWeb) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('[EntitlementService] logOut failed: $e');
    }
  }

  /// Returns the current RevenueCat App User ID — the value testers
  /// need to send to grant a promotional entitlement from the RC
  /// dashboard. Anonymous (`$RCAnonymousID:...`) before sign-in, equal
  /// to the Supabase UUID after [linkUser] runs. Returns null on web /
  /// failure so the UI can hide the copy affordance.
  Future<String?> currentAppUserId() async {
    if (!_supported) return null;
    try {
      return await Purchases.appUserID;
    } catch (e) {
      debugPrint('[EntitlementService] appUserID failed: $e');
      return null;
    }
  }

  /// Restores prior purchases for the current store account.
  Future<CustomerInfo> restorePurchases() async {
    try {
      return await Purchases.restorePurchases();
    } catch (e) {
      throw _mapPurchaseError(e);
    }
  }

  /// Maps the platform exception RevenueCat throws into our typed hierarchy.
  Object _mapPurchaseError(Object e) {
    if (e is PlatformException) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        return const UserCancelledPurchaseException();
      }
      if (code == PurchasesErrorCode.networkError) {
        return const EntitlementNetworkException();
      }
      return EntitlementUnknownException(e.message ?? 'Unknown purchase error');
    }
    return EntitlementUnknownException(
      e is Exception ? e.toString() : 'Unknown purchase error',
    );
  }
}
