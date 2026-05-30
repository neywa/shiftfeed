import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Feed layout choice. Persisted across launches via [SharedPreferences]
/// under [_kViewModePref].
enum ViewMode { grid, list }

const String _kViewModePref = 'view_mode';

class LayoutNotifier extends ChangeNotifier {
  ViewMode _mode;

  LayoutNotifier({required ViewMode initial}) : _mode = initial;

  ViewMode get mode => _mode;

  void setMode(ViewMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kViewModePref, _mode.name);
    } catch (e) {
      debugPrint('[LayoutNotifier] persist failed: $e');
    }
  }

  /// Reads the persisted [ViewMode], defaulting to [ViewMode.grid] on
  /// first launch or read failure. Call this in `main()` before
  /// constructing the notifier so the UI renders the persisted value on
  /// the very first frame.
  static Future<ViewMode> loadInitial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kViewModePref);
      return ViewMode.values.firstWhere(
        (m) => m.name == raw,
        orElse: () => ViewMode.grid,
      );
    } catch (_) {
      return ViewMode.grid;
    }
  }
}
