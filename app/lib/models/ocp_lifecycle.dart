import 'package:flutter/material.dart';

/// Red Hat OpenShift Container Platform support phase for a minor version.
enum OcpSupportPhase {
  fullSupport,
  maintenance,
  eus,
  endOfLife,
  unknown;

  /// Uppercase badge text. Kept short to fit the pill (fontSize 9); the
  /// longest, 'FULL SUPPORT', is about the max the pill holds.
  String get label => switch (this) {
    OcpSupportPhase.fullSupport => 'FULL SUPPORT',
    OcpSupportPhase.maintenance => 'MAINTENANCE',
    OcpSupportPhase.eus => 'EUS',
    OcpSupportPhase.endOfLife => 'END OF LIFE',
    OcpSupportPhase.unknown => 'UNKNOWN',
  };

  /// Badge accent + card stripe colour.
  ///
  /// EUS gets its **own** colour (blue), deliberately not folded into the
  /// amber Maintenance bucket: an even-numbered EUS release can legitimately
  /// outlive a newer standard release that's still in Maintenance, and the
  /// old sort-position badges rendered that backwards. A distinct colour is
  /// what makes "older but still supported" legible.
  Color get color => switch (this) {
    OcpSupportPhase.fullSupport => const Color(0xFF00AA44), // green
    OcpSupportPhase.maintenance => const Color(0xFFFFAA00), // amber
    OcpSupportPhase.eus => const Color(0xFF3B82F6), // blue
    OcpSupportPhase.endOfLife => const Color(0xFF555555), // grey
    OcpSupportPhase.unknown => const Color(0xFF777777), // neutral grey
  };
}

/// Lifecycle boundaries supplied by Red Hat's Product Life Cycle API.
///
/// `eusEnd` is the latest published date across Extended Update Support and
/// its Terms 2 and 3. Dates are stored as UTC calendar dates by the scraper.
class OcpLifecycleEntry {
  final DateTime ga;
  final bool isEus;
  final DateTime fullSupportEnd;
  final DateTime maintenanceEnd;
  final DateTime? eusEnd;

  const OcpLifecycleEntry({
    required this.ga,
    required this.isEus,
    required this.fullSupportEnd,
    required this.maintenanceEnd,
    this.eusEnd,
  });
}

/// Resolves the current phase from lifecycle data fetched with the version.
/// Missing data remains explicitly `unknown` until the next scraper sync.
OcpSupportPhase ocpPhaseFor(OcpLifecycleEntry? entry, {DateTime? now}) {
  if (entry == null) return OcpSupportPhase.unknown;

  final t = (now ?? DateTime.now()).toUtc();
  if (t.isBefore(entry.fullSupportEnd)) return OcpSupportPhase.fullSupport;
  if (t.isBefore(entry.maintenanceEnd)) return OcpSupportPhase.maintenance;
  if (entry.isEus && entry.eusEnd != null && t.isBefore(entry.eusEnd!)) {
    return OcpSupportPhase.eus;
  }
  return OcpSupportPhase.endOfLife;
}
