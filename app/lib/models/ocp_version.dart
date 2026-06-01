import 'package:flutter/foundation.dart';

// Minor versions below this are considered EOL and hidden from the UI.
// Mirrors `ACTIVE_MINOR_MINIMUM` in scraper/sources/ocp_versions.py.
const int kOcpActiveMinorMinimum = 14;

class OcpVersion {
  final String id;
  final String minorVersion;
  final String latestStable;
  final DateTime updatedAt;

  const OcpVersion({
    required this.id,
    required this.minorVersion,
    required this.latestStable,
    required this.updatedAt,
  });

  factory OcpVersion.fromJson(Map<String, dynamic> json) {
    return OcpVersion(
      id: json['id'] as String,
      minorVersion: json['minor_version'] as String,
      latestStable: json['latest_stable'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    );
  }

  /// Parses a list of raw rows, skipping (and logging) any malformed row so
  /// a single bad row — e.g. a freshly-seeded channel with a null
  /// `latest_stable` — can't throw and discard the entire list.
  static List<OcpVersion> parseList(List<dynamic> rows) {
    final result = <OcpVersion>[];
    for (final row in rows) {
      try {
        result.add(OcpVersion.fromJson(row as Map<String, dynamic>));
      } catch (e) {
        debugPrint('OcpVersion: skipping malformed row: $e');
      }
    }
    return result;
  }

  /// Numeric minor (the `N` in `4.N`). Returns -1 for a malformed
  /// `minor_version` (missing `.` or non-numeric minor) so it's naturally
  /// excluded by the `>= kOcpActiveMinorMinimum` filter instead of throwing.
  int get minorInt {
    final parts = minorVersion.split('.');
    if (parts.length < 2) return -1;
    return int.tryParse(parts[1]) ?? -1;
  }
}
