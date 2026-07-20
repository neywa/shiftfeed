import 'package:flutter/material.dart';

/// Red Hat OpenShift Container Platform support phase for a minor version.
///
/// Drives the status badge on the Versions screen. The enum owns its badge
/// label and colour (same "one enum is the source of truth" pattern as
/// [CveSeverity] in `cve_severity.dart`) so the two can't drift apart.
///
/// Order matters: phases run fullSupport -> maintenance -> (eus) -> endOfLife.
/// `unknown` is the honest fallback for a minor that isn't in [kOcpLifecycle]
/// yet (e.g. a brand-new GA not hand-added) — it renders a neutral badge
/// rather than silently landing in a misleading bucket.
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

/// One version's published lifecycle boundaries.
///
/// Stores the phase-end **dates directly** (as published) rather than deriving
/// them from GA + policy math — more robust and an exact match to Red Hat's
/// tables. `ga` is informational; only the three `*End` dates drive
/// [ocpPhaseFor]. `eusEnd` is null for standard (odd) releases.
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

/// Hardcoded Red Hat OpenShift Container Platform lifecycle reference table,
/// keyed by minor version ('4.14'..'4.22'). Covers back to
/// `kOcpActiveMinorMinimum` (14) in `ocp_version.dart`.
///
/// ⚠️ MANUAL UPKEEP REQUIRED. These values are hand-transcribed from Red Hat's
/// OCP Life Cycle Policy (https://access.redhat.com/support/policy/updates/openshift,
/// cross-checked against endoflife.date and Microsoft's ARO lifecycle table).
/// They MUST be updated by hand whenever a new minor GAs or Red Hat shifts a
/// phase-end date — nothing refreshes them automatically.
///
/// This is a TEMPORARY measure. The tracked follow-up (Option B) moves this
/// data into the scraper so it's pulled live from Red Hat instead of hardcoded
/// here; when that lands, this table and [ocpPhaseFor] should be retired in
/// favour of a real column on `ocp_versions`.
///
/// A minor absent from this map resolves to [OcpSupportPhase.unknown] — keep
/// the table ahead of newly-GA'd versions so they don't render 'UNKNOWN'.
final Map<String, OcpLifecycleEntry> kOcpLifecycle = {
  '4.14': OcpLifecycleEntry(
    ga: DateTime.utc(2023, 10, 31),
    isEus: true,
    fullSupportEnd: DateTime.utc(2024, 5, 27),
    maintenanceEnd: DateTime.utc(2025, 5, 1),
    eusEnd: DateTime.utc(2025, 10, 31),
  ),
  '4.15': OcpLifecycleEntry(
    ga: DateTime.utc(2024, 2, 27),
    isEus: false,
    fullSupportEnd: DateTime.utc(2024, 9, 27),
    maintenanceEnd: DateTime.utc(2025, 8, 27),
  ),
  '4.16': OcpLifecycleEntry(
    ga: DateTime.utc(2024, 6, 27),
    isEus: true,
    fullSupportEnd: DateTime.utc(2025, 1, 1),
    maintenanceEnd: DateTime.utc(2025, 12, 27),
    eusEnd: DateTime.utc(2026, 6, 27),
  ),
  '4.17': OcpLifecycleEntry(
    ga: DateTime.utc(2024, 10, 1),
    isEus: false,
    fullSupportEnd: DateTime.utc(2025, 5, 25),
    maintenanceEnd: DateTime.utc(2026, 4, 1),
  ),
  '4.18': OcpLifecycleEntry(
    ga: DateTime.utc(2025, 2, 25),
    isEus: true,
    fullSupportEnd: DateTime.utc(2025, 9, 17),
    maintenanceEnd: DateTime.utc(2026, 8, 25),
    eusEnd: DateTime.utc(2027, 2, 25),
  ),
  '4.19': OcpLifecycleEntry(
    ga: DateTime.utc(2025, 6, 17),
    isEus: false,
    fullSupportEnd: DateTime.utc(2026, 1, 21),
    maintenanceEnd: DateTime.utc(2026, 12, 17),
  ),
  '4.20': OcpLifecycleEntry(
    ga: DateTime.utc(2025, 10, 21),
    isEus: true,
    fullSupportEnd: DateTime.utc(2026, 5, 3),
    maintenanceEnd: DateTime.utc(2027, 4, 21),
    eusEnd: DateTime.utc(2027, 10, 21),
  ),
  // GA day is a placeholder — Red Hat published "February 2026" without a day.
  // The phase-end dates below (which actually drive the badge) are firm.
  '4.21': OcpLifecycleEntry(
    ga: DateTime.utc(2026, 2, 24),
    isEus: false,
    fullSupportEnd: DateTime.utc(2026, 9, 9),
    maintenanceEnd: DateTime.utc(2027, 8, 3),
  ),
  '4.22': OcpLifecycleEntry(
    ga: DateTime.utc(2026, 6, 9),
    isEus: true,
    fullSupportEnd: DateTime.utc(2026, 12, 31),
    maintenanceEnd: DateTime.utc(2027, 12, 31),
    eusEnd: DateTime.utc(2028, 6, 9),
  ),
};

/// Resolves a minor version's current support phase by comparing [now]
/// against its published phase-end dates.
///
/// [now] is injectable purely so tests can pin a fixed date; production call
/// sites pass nothing and get `DateTime.now()`. Comparisons use UTC so a
/// device timezone can't shift a boundary by a day.
///
/// A minor not in [kOcpLifecycle] returns [OcpSupportPhase.unknown] — never a
/// guessed bucket.
OcpSupportPhase ocpPhaseFor(String minorVersion, {DateTime? now}) {
  final entry = kOcpLifecycle[minorVersion];
  if (entry == null) return OcpSupportPhase.unknown;

  final t = (now ?? DateTime.now()).toUtc();
  if (t.isBefore(entry.fullSupportEnd)) return OcpSupportPhase.fullSupport;
  if (t.isBefore(entry.maintenanceEnd)) return OcpSupportPhase.maintenance;
  if (entry.isEus &&
      entry.eusEnd != null &&
      t.isBefore(entry.eusEnd!)) {
    return OcpSupportPhase.eus;
  }
  return OcpSupportPhase.endOfLife;
}

/// Whether a minor is EUS-eligible (Red Hat grants Extended Update Support to
/// even-numbered minors).
///
/// This is a **static property of the release**, independent of its current
/// [ocpPhaseFor] — a version is "an EUS release" from GA, long before it
/// actually enters the EUS window. A minor absent from [kOcpLifecycle] returns
/// false — never a guess, same policy as [ocpPhaseFor]'s `unknown`.
bool ocpIsEus(String minorVersion) =>
    kOcpLifecycle[minorVersion]?.isEus ?? false;
