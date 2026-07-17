// Tests for the shared selection controls' foreground contrast.
//
// Background: the CVE screen shipped a bespoke chip whose label was
// kTextMuted #555555 on a transparent fill — 2.61:1 against the dark
// background, failing WCAG's 4.5:1 for text and its 3:1 for UI. The fix
// was to reuse the feed's pill (a surface2 body + kTextSecondary, 4.38:1).
//
// The trap that makes this more than a copy-paste: the feed's pill
// hardcoded `Colors.white` on the selected fill. That's fine for every
// color the FEED passes, but the CVE screen passes the severity palette,
// and white on the severity amber #FFAA00 is 1.91:1 — worse than the bug
// being fixed. Hence onAccent(). These tests pin its two load-bearing
// properties: the feed didn't change, and amber did.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/cve_severity.dart';
import 'package:shiftfeed/theme/app_theme.dart';
import 'package:shiftfeed/widgets/filter_pill.dart';

/// WCAG 2.x relative contrast ratio. Re-derived here rather than imported
/// because the ratio is the whole point of onAccent — a test that reused
/// the app's own math could agree with a broken implementation.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Every color HomeScreen passes as a FilterPill/ToggleButton
/// `selectedColor`. Mirrors the private constants in home_screen.dart.
const _feedAccents = <String, Color>{
  'kRed (ALL / per-source chips, Latest/Top)': kRed,
  'releaseGreen (RELEASES, OCP)': Color(0xFF00AA44),
  'securityOrange (SECURITY)': Color(0xFFFF6600),
};

void main() {
  group('feed is unchanged by the extraction', () {
    // THE regression guard for pulling _mobileChip out of HomeScreen.
    // Before onAccent() the feed's selected chips were `Colors.white`,
    // full stop. If any feed accent resolves to black now, the extraction
    // silently restyled a shipped screen.
    _feedAccents.forEach((name, color) {
      test('$name still resolves to white', () {
        expect(onAccent(color), Colors.white);
      });
    });

    test('every feed accent sits clear of the threshold', () {
      // Not just "below" — clear of it. A feed color drifting to within a
      // rounding error of the boundary is how this flips unnoticed.
      for (final entry in _feedAccents.entries) {
        final lum = entry.value.computeLuminance();
        expect(
          lum,
          lessThan(kAccentLuminanceThreshold - 0.05),
          reason: '${entry.key} (lum $lum) is too close to the threshold',
        );
      }
    });
  });

  group('the amber fix', () {
    final amber = CveSeverity.medium.color;

    test('severity amber is #FFAA00 — the color that forced onAccent', () {
      expect(amber.toARGB32(), 0xFFFFAA00);
    });

    test('amber gets black text, not white', () {
      expect(onAccent(amber), Colors.black);
    });

    test('white on amber would have been illegible', () {
      // Documents the bug this prevents: 1.91:1, worse than the 2.61:1
      // the whole change set out to fix.
      expect(_contrast(Colors.white, amber), lessThan(2.0));
    });

    test('the black onAccent picks clears WCAG AA for text', () {
      expect(_contrast(onAccent(amber), amber), greaterThan(4.5));
    });

    test('amber sits clear of the threshold on the other side', () {
      // Amber measures 0.5001. The conventional `luminance > 0.5` rule
      // would decide it by 0.0001 — a coin flip that any palette tweak
      // could lose. This asserts the margin the 0.40 threshold buys.
      expect(
        amber.computeLuminance(),
        greaterThan(kAccentLuminanceThreshold + 0.05),
      );
    });
  });

  group('every severity bucket is readable when selected', () {
    for (final s in CveSeverity.values) {
      test('${s.label} clears the feed baseline', () {
        // The floor is 2.9:1, not WCAG's 3:1, and that is deliberate:
        // CveSeverity.high is #FF6600 — the SAME orange as the feed's
        // shipped SECURITY chip, at 2.94:1. Unifying with the feed means
        // inheriting it. Raising this floor requires darkening the shared
        // orange, which fixes both screens at once; tracked separately.
        expect(
          _contrast(onAccent(s.color), s.color),
          greaterThan(2.9),
          reason: '${s.label} is less readable than the feed\'s worst chip',
        );
      });
    }

    test('all four still beat the bug they replaced', () {
      // The bespoke chip's label was 2.61:1. No bucket may regress past
      // that, or the "fix" made something worse.
      for (final s in CveSeverity.values) {
        expect(_contrast(onAccent(s.color), s.color), greaterThan(2.61));
      }
    });
  });

  group('FilterPill.heightOf', () {
    // MainAppBar reads bottomHeight BEFORE `bottom` is laid out, so the
    // feed has to reserve the pill's height in advance. That number used
    // to be hand-derived at the call site from constants this widget
    // owns; if it under-reports, the app bar overflows.
    testWidgets('reserves at least the rendered pill height', (tester) async {
      late double reserved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                reserved = FilterPill.heightOf(context);
                return Center(
                  child: FilterPill(
                    label: 'SECURITY',
                    selected: false,
                    onTap: () {},
                  ),
                );
              },
            ),
          ),
        ),
      );
      final rendered = tester.getSize(find.byType(FilterPill)).height;
      expect(reserved, greaterThanOrEqualTo(rendered));
    });

    testWidgets('reserves enough in an AppBar bottom, as the feed uses it',
        (tester) async {
      // The shape that actually ships: heightOf() is called with
      // HomeScreen's context, but the pills render inside the AppBar's
      // `bottom`, which can impose its own DefaultTextStyle. If those two
      // disagree, the reservation is wrong in production and no
      // body-rendered test would show it. An overflow throws here.
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                bottom: PreferredSize(
                  // Mirrors home_screen's `bottomHeight: 16 + …`.
                  preferredSize:
                      Size.fromHeight(16 + FilterPill.heightOf(context)),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        for (final label in ['ALL', 'RELEASES', 'SECURITY'])
                          FilterPill(
                            label: label,
                            selected: label == 'ALL',
                            onTap: () {},
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              body: const SizedBox(),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still reserves enough at a large text scale', (tester) async {
      // The getter scales with textScaler; a fixed constant would
      // overflow for users with large system type.
      late double reserved;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  reserved = FilterPill.heightOf(context);
                  return Center(
                    child: FilterPill(
                      label: 'SECURITY',
                      selected: false,
                      onTap: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      final rendered = tester.getSize(find.byType(FilterPill)).height;
      expect(reserved, greaterThanOrEqualTo(rendered));
    });
  });
}
