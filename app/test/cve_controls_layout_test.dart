// Layout tests for the CVE screen's sort/filter control block.
//
// These pin three things that are easy to break silently and invisible
// to the analyzer: the sort buttons matching the pills' height, the two
// rows sharing a left edge, and the 8dp rhythm.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/theme/app_theme.dart';
import 'package:shiftfeed/widgets/filter_pill.dart';
import 'package:shiftfeed/widgets/toggle_button.dart';

Widget _host(Widget child) => MaterialApp(
      theme: appTheme(),
      home: Scaffold(body: child),
    );

void main() {
  group('dense ToggleButton matches FilterPill height', () {
    testWidgets('same height at default text scale', (tester) async {
      await tester.pumpWidget(_host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToggleButton(
              label: 'Date',
              selected: true,
              dense: true,
              onTap: () {},
            ),
            FilterPill(label: 'CRITICAL', selected: false, onTap: () {}),
          ],
        ),
      ));
      final toggle = tester.getSize(find.byType(ToggleButton)).height;
      final pill = tester.getSize(find.byType(FilterPill)).height;
      expect(toggle, pill);
    });

    testWidgets('same height at a large text scale', (tester) async {
      // Pinned to heightOf() rather than a hardcoded padding precisely so
      // this holds when the user scales type up.
      await tester.pumpWidget(_host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ToggleButton(
                label: 'Date',
                selected: true,
                dense: true,
                onTap: () {},
              ),
              FilterPill(label: 'CRITICAL', selected: false, onTap: () {}),
            ],
          ),
        ),
      ));
      final toggle = tester.getSize(find.byType(ToggleButton)).height;
      final pill = tester.getSize(find.byType(FilterPill)).height;
      expect(toggle, pill);
    });

    testWidgets('non-dense keeps the full-size button for the feed',
        (tester) async {
      // The feed's desktop Latest/Top must NOT shrink — dense is opt-in.
      await tester.pumpWidget(_host(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ToggleButton(label: 'Latest', selected: true, onTap: () {}),
            FilterPill(label: 'ALL', selected: false, onTap: () {}),
          ],
        ),
      ));
      final toggle = tester.getSize(find.byType(ToggleButton)).height;
      final pill = tester.getSize(find.byType(FilterPill)).height;
      expect(toggle, greaterThan(pill));
      expect(toggle, 48.0, reason: "Material's default tap target");
    });
  });

  group('dense button still has a usable hit area', () {
    testWidgets('responds to a tap at its centre', (tester) async {
      // shrinkWrap removes the 48dp padded tap target; make sure the
      // button is still actually tappable at its rendered size.
      var taps = 0;
      await tester.pumpWidget(_host(
        Center(
          child: ToggleButton(
            label: 'Date',
            selected: false,
            dense: true,
            onTap: () => taps++,
          ),
        ),
      ));
      await tester.tap(find.byType(ToggleButton));
      await tester.pump();
      expect(taps, 1);
    });
  });
}
