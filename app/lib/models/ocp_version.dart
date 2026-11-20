import 'package:flutter/foundation.dart';

import 'ocp_lifecycle.dart';

// OpenShift 3 is EOL. Within the 4.x stream, versions below 4.14 are also
// EOL. Mirrors the active-version constants in scraper/sources/ocp_versions.py.
const int kOcpActiveMajorMinimum = 4;
const int kOcpActive4MinorMinimum = 14;

class OcpVersion {
  final String id;
  final String minorVersion;
  final String latestStable;
  final DateTime updatedAt;
  final OcpLifecycleEntry? lifecycle;

  const OcpVersion({
    required this.id,
    required this.minorVersion,
    required this.latestStable,
    required this.updatedAt,
    this.lifecycle,
  });

  factory OcpVersion.fromJson(Map<String, dynamic> json) {
    return OcpVersion(
      id: json['id'] as String,
      minorVersion: json['minor_version'] as String,
      latestStable: json['latest_stable'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      lifecycle: _parseLifecycle(json),
    );
  }

  static OcpLifecycleEntry? _parseLifecycle(Map<String, dynamic> json) {
    final ga = _parseUtcDate(json['ga']);
    final fullSupportEnd = _parseUtcDate(json['full_support_end']);
    final maintenanceEnd = _parseUtcDate(json['maintenance_end']);
    final isEus = json['is_eus'];
    if (ga == null ||
        fullSupportEnd == null ||
        maintenanceEnd == null ||
        isEus is! bool) {
      return null;
    }
    return OcpLifecycleEntry(
      ga: ga,
      isEus: isEus,
      fullSupportEnd: fullSupportEnd,
      maintenanceEnd: maintenanceEnd,
      eusEnd: _parseUtcDate(json['eus_end']),
    );
  }

  static DateTime? _parseUtcDate(dynamic value) {
    if (value is! String) return null;
    return DateTime.tryParse(value)?.toUtc();
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

  /// Numeric major (the `M` in `M.N`). Returns -1 for a malformed channel.
  int get majorInt => _channelPart(0);

  /// Numeric minor (the `N` in `M.N`). Returns -1 for a malformed channel.
  int get minorInt {
    return _channelPart(1);
  }

  /// Whether this channel is supported by the scraper and should be shown.
  /// Future major streams are active automatically; the EOL cutoff applies
  /// only to the 4.x stream.
  bool get isActive =>
      majorInt > kOcpActiveMajorMinimum ||
      (majorInt == kOcpActiveMajorMinimum &&
          minorInt >= kOcpActive4MinorMinimum);

  /// Numeric comparison by major, then minor. A malformed channel sorts
  /// before valid channels, so consumers can safely sort before filtering.
  int compareChannelTo(OcpVersion other) {
    final majorComparison = majorInt.compareTo(other.majorInt);
    return majorComparison != 0
        ? majorComparison
        : minorInt.compareTo(other.minorInt);
  }

  int _channelPart(int index) {
    final parts = minorVersion.split('.');
    if (parts.length != 2) return -1;
    return int.tryParse(parts[index]) ?? -1;
  }
}
