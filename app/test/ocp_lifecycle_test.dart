import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/ocp_lifecycle.dart';

final lifecycle = OcpLifecycleEntry(
  ga: DateTime.utc(2025, 2, 25),
  isEus: true,
  fullSupportEnd: DateTime.utc(2025, 9, 17),
  maintenanceEnd: DateTime.utc(2026, 8, 25),
  // The final EUS term, rather than only the base-term end.
  eusEnd: DateTime.utc(2028, 2, 25),
);

void main() {
  group('ocpPhaseFor', () {
    test('uses API lifecycle boundaries', () {
      expect(
        ocpPhaseFor(lifecycle, now: DateTime.utc(2025, 5)),
        OcpSupportPhase.fullSupport,
      );
      expect(
        ocpPhaseFor(lifecycle, now: DateTime.utc(2026, 1)),
        OcpSupportPhase.maintenance,
      );
      expect(
        ocpPhaseFor(lifecycle, now: DateTime.utc(2027, 1)),
        OcpSupportPhase.eus,
      );
      expect(
        ocpPhaseFor(lifecycle, now: DateTime.utc(2028, 3)),
        OcpSupportPhase.endOfLife,
      );
    });

    test('returns unknown while a row has not yet been lifecycle-synced', () {
      expect(ocpPhaseFor(null), OcpSupportPhase.unknown);
    });
  });

  test('badge vocabulary and colours are stable', () {
    expect(OcpSupportPhase.eus.label, 'EUS');
    expect(OcpSupportPhase.eus.color, const Color(0xFF3B82F6));
  });
}
