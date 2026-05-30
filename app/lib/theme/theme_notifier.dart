import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kDarkModePref = 'dark_mode';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode;

  ThemeNotifier({required ThemeMode initial}) : _mode = initial;

  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDarkModePref, isDark);
    } catch (e) {
      debugPrint('[ThemeNotifier] persist failed: $e');
    }
  }

  /// Reads the persisted dark-mode flag, defaulting to dark on first
  /// launch (mirrors the prior in-memory default). Call in `main()`
  /// before constructing the notifier so the very first frame renders
  /// with the persisted theme.
  static Future<ThemeMode> loadInitial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDark = prefs.getBool(_kDarkModePref) ?? true;
      return isDark ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      return ThemeMode.dark;
    }
  }
}
