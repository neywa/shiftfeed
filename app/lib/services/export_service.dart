/// Handles sharing the daily AI briefing via the system share sheet.
///
/// This is the only file in the app that imports `share_plus` — all other
/// code goes through [ExportService.instance].
library;

import 'package:share_plus/share_plus.dart';

class ExportService {
  ExportService._();
  static final ExportService _instance = ExportService._();
  static ExportService get instance => _instance;

  /// Shares the provided digest text via the system share sheet as plain
  /// text. The caller is expected to have a non-empty digest in hand —
  /// this method does not check.
  Future<void> shareDigest(String digestText) async {
    await Share.share(digestText, subject: 'ShiftFeed Daily Briefing');
  }
}
