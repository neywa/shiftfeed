import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Lightweight wrapper around `connectivity_plus` exposing a single
/// `isOnline` flag. Treated as a HINT, not a guarantee — the connectivity
/// API only reports interface state ("Wi-Fi is up"), not reachability of
/// the Supabase backend. Repository calls remain the ground truth via
/// [RepoException]. This notifier exists to drive the user-facing
/// "You're offline" indicator and to let UI suppress noisy retries when
/// the OS already knows there's no link.
///
/// Singleton + [ChangeNotifier] so it composes with the existing
/// `MultiProvider` setup in `main.dart` alongside `ThemeNotifier` /
/// `LayoutNotifier`.
class ConnectivityNotifier extends ChangeNotifier {
  ConnectivityNotifier._();
  static final ConnectivityNotifier instance = ConnectivityNotifier._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;
  bool _initialised = false;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  /// Idempotent. Reads the current connectivity state once and starts
  /// listening for changes. Safe to call from `main()` before `runApp`.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final initial = await _connectivity.checkConnectivity();
      _isOnline = _resultIsOnline(initial);
    } catch (e) {
      // Some platforms (or first-launch web) can throw here. Default to
      // online — false-negative on the banner is worse than no banner.
      debugPrint('[Connectivity] initial check failed: $e');
      _isOnline = true;
    }
    _sub = _connectivity.onConnectivityChanged.listen(
      (results) {
        final online = _resultIsOnline(results);
        if (online == _isOnline) return;
        _isOnline = online;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('[Connectivity] stream error: $e');
      },
    );
  }

  /// `connectivity_plus` returns a list because a device can be on Wi-Fi
  /// AND mobile data simultaneously. We're online if any non-`none`
  /// transport is present.
  bool _resultIsOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
