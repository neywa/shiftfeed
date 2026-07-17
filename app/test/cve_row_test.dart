// Widget tests for the CVE row's badge rendering.
//
// The gap these close: `article_card.dart` styles only critical/important/
// moderate, so an NVD-sourced `high` or `medium` renders as a plain
// SECURITY badge and the user can't see the severity at all. The CVE
// screen must style all four normalized buckets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/cve_severity.dart';

void main() {
  group('every normalized bucket renders a styled badge', () {
    // Drives the same mapping the row widget uses. Building the real
    // _CveRow needs an Article + a Navigator + google_fonts; the mapping
    // is where the bug lives, so pin that directly.
    for (final raw in [
      // Red Hat vocabulary
      'critical', 'important', 'moderate', 'low',
      // NVD vocabulary
      'high', 'medium',
    ]) {
      testWidgets('"$raw" gets a severity badge, not a generic fallback',
          (tester) async {
        final severity = CveSeverity.fromWord(raw);
        expect(
          severity,
          isNotNull,
          reason: '"$raw" fell through to the unstyled generic badge',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Container(
                  color: severity!.color.withValues(alpha: 0.15),
                  child: Text(severity.label),
                ),
              ),
            ),
          ),
        );

        expect(find.text(severity.label), findsOneWidget);
      });
    }
  });

  testWidgets('the two vocabularies collapse to one badge per bucket',
      (tester) async {
    // 'important' (Red Hat) and 'high' (NVD) must be indistinguishable
    // once displayed — that's the whole point of the normalization.
    expect(
      CveSeverity.fromWord('important')!.label,
      CveSeverity.fromWord('high')!.label,
    );
    expect(
      CveSeverity.fromWord('moderate')!.color,
      CveSeverity.fromWord('medium')!.color,
    );
  });
}
