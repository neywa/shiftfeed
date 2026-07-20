// Unit tests for the OpenShift lifecycle phase computation that drives the
// Versions screen status badges.
//
// The badge used to be computed from sort position, which produced a confirmed
// inversion: 4.18 (EUS, supported longer) rendered "below" 4.19 (standard,
// EOLs sooner). These tests pin the date-driven phase for every tracked
// version and, specifically, guard that exact inversion so it can't regress.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/ocp_lifecycle.dart';

void main() {
  // "Today" for the snapshot assertions — matches the plan's rendered table.
  final today = DateTime.utc(2026, 7, 20);

  group('ocpPhaseFor — snapshot as of 2026-07-20', () {
    // The full 4.14–4.22 cross-check. This is the executable form of the
    // per-version table reviewed against Red Hat's published lifecycle.
    final expected = <String, OcpSupportPhase>{
      '4.22': OcpSupportPhase.fullSupport,
      '4.21': OcpSupportPhase.fullSupport, // two versions in full support is real
      '4.20': OcpSupportPhase.maintenance,
      '4.19': OcpSupportPhase.maintenance,
      '4.18': OcpSupportPhase.maintenance, // enters EUS on 2026-08-25
      '4.17': OcpSupportPhase.endOfLife,
      '4.16': OcpSupportPhase.endOfLife, // EUS ended 2026-06-27
      '4.15': OcpSupportPhase.endOfLife,
      '4.14': OcpSupportPhase.endOfLife,
    };

    expected.forEach((minor, phase) {
      test('$minor -> ${phase.name}', () {
        expect(ocpPhaseFor(minor, now: today), phase);
      });
    });
  });

  group('4.18 / 4.19 inversion is fixed and pinned', () {
    test('today both are Maintenance — 4.18 never renders below 4.19', () {
      expect(ocpPhaseFor('4.18', now: today), OcpSupportPhase.maintenance);
      expect(ocpPhaseFor('4.19', now: today), OcpSupportPhase.maintenance);
    });

    test('2027-01-15: older EUS 4.18 still supported while newer 4.19 is EOL', () {
      // The precise window the old positional logic got backwards: 4.19
      // (standard) has reached End of Life, but 4.18 (EUS) is still supported.
      final t = DateTime.utc(2027, 1, 15);
      expect(ocpPhaseFor('4.18', now: t), OcpSupportPhase.eus);
      expect(ocpPhaseFor('4.19', now: t), OcpSupportPhase.endOfLife);
    });
  });

  group('phase boundaries transition on the published dates', () {
    test('4.18 flips Maintenance -> EUS across 2026-08-25', () {
      expect(
        ocpPhaseFor('4.18', now: DateTime.utc(2026, 8, 24)),
        OcpSupportPhase.maintenance,
      );
      expect(
        ocpPhaseFor('4.18', now: DateTime.utc(2026, 8, 26)),
        OcpSupportPhase.eus,
      );
    });

    test('4.18 flips EUS -> End of Life across 2027-02-25', () {
      expect(
        ocpPhaseFor('4.18', now: DateTime.utc(2027, 2, 24)),
        OcpSupportPhase.eus,
      );
      expect(
        ocpPhaseFor('4.18', now: DateTime.utc(2027, 2, 26)),
        OcpSupportPhase.endOfLife,
      );
    });

    test('4.19 (standard) flips Maintenance -> End of Life across 2026-12-17', () {
      expect(
        ocpPhaseFor('4.19', now: DateTime.utc(2026, 12, 16)),
        OcpSupportPhase.maintenance,
      );
      expect(
        ocpPhaseFor('4.19', now: DateTime.utc(2026, 12, 18)),
        OcpSupportPhase.endOfLife,
      );
    });
  });

  group('unknown fallback — never a guessed bucket', () {
    test('a minor absent from the table resolves to unknown', () {
      expect(ocpPhaseFor('4.99', now: today), OcpSupportPhase.unknown);
      expect(ocpPhaseFor('4.13', now: today), OcpSupportPhase.unknown);
      expect(ocpPhaseFor('garbage', now: today), OcpSupportPhase.unknown);
    });
  });

  group('vocabulary + colour are pinned (no silent drift)', () {
    test('labels match the agreed Red Hat phase names', () {
      expect(OcpSupportPhase.fullSupport.label, 'FULL SUPPORT');
      expect(OcpSupportPhase.maintenance.label, 'MAINTENANCE');
      expect(OcpSupportPhase.eus.label, 'EUS');
      expect(OcpSupportPhase.endOfLife.label, 'END OF LIFE');
      expect(OcpSupportPhase.unknown.label, 'UNKNOWN');
    });

    test('colours match the agreed palette', () {
      expect(OcpSupportPhase.fullSupport.color, const Color(0xFF00AA44));
      expect(OcpSupportPhase.maintenance.color, const Color(0xFFFFAA00));
      expect(OcpSupportPhase.eus.color, const Color(0xFF3B82F6));
      expect(OcpSupportPhase.endOfLife.color, const Color(0xFF555555));
      expect(OcpSupportPhase.unknown.color, const Color(0xFF777777));
    });

    test('EUS is a distinct colour from Maintenance', () {
      // The whole point of the fix: an EUS release must not read as the same
      // amber bucket as Maintenance.
      expect(
        OcpSupportPhase.eus.color == OcpSupportPhase.maintenance.color,
        isFalse,
      );
    });
  });
}
