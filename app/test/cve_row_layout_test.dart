// Layout tests for the CVE row's header line.
//
// Severity badge, CVSS score and CVE id(s) were folded onto one line to
// shrink the card. What can go wrong is invisible to the analyzer: the
// header overflowing at a real phone width (a render error, not a compile
// one), or the card quietly growing a second header line back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/models/article.dart';
import 'package:shiftfeed/screens/cve_screen.dart';
import 'package:shiftfeed/theme/app_theme.dart';

Article _article({
  required List<String> tags,
  String title = 'QUAY v3.10.24 released',
}) =>
    Article.fromJson({
      'id': 'https://x',
      'title': title,
      'url': 'https://x',
      'source': 'GitHub Releases',
      'tags': tags,
      'summary': null,
      'published_at': '2026-07-16T09:00:00+00:00',
      'created_at': '2026-07-16T09:00:00+00:00',
    });

/// Renders the real [CveRow] at this device's actual phone width — the
/// header overflows only at a realistic width, so a default 800x600 test
/// surface would pass while the phone renders a yellow overflow stripe.
Future<double> _rowHeight(WidgetTester tester, Article article) async {
  tester.view.physicalSize = const Size(1080, 2316);
  tester.view.devicePixelRatio = 2.8125;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: appTheme(),
    home: Scaffold(
      body: CveRow(article: article, onTap: () {}),
    ),
  ));
  return tester.getSize(find.byType(CveRow)).height;
}

void main() {
  testWidgets('single-CVE row does not overflow', (tester) async {
    await _rowHeight(
      tester,
      _article(tags: ['cve', 'CVE-2026-12143', 'important', 'cvss:7.5']),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('multi-CVE row wraps instead of overflowing', (tester) async {
    // The real case from the feed: two ids plus both badges plus the date
    // cannot fit one line at phone width, so the ids Text must soft-wrap
    // inside the Wrap rather than run off the card.
    await _rowHeight(
      tester,
      _article(
        tags: [
          'cve',
          'CVE-2023-39500',
          'CVE-2022-24999',
          'important',
          'cvss:7.8',
        ],
        title: 'Dependency analytics 1.0: AI coding with supply chain security',
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('folding the header onto one line shrinks the card',
      (tester) async {
    // A single-CVE card must be shorter than a two-line-header one — this
    // is the whole point of the change. If someone splits the ids back onto
    // their own row, these converge.
    final single = await _rowHeight(
      tester,
      _article(tags: ['cve', 'CVE-2026-12143', 'important', 'cvss:7.5']),
    );
    final wrapped = await _rowHeight(
      tester,
      _article(tags: [
        'cve',
        'CVE-2023-39500',
        'CVE-2022-24999',
        'important',
        'cvss:7.8',
      ]),
    );
    expect(
      single,
      lessThan(wrapped),
      reason: 'single-CVE header should occupy one line, not two',
    );
  });

  testWidgets('an unscored, unsevere CVE article still renders',
      (tester) async {
    // cve_tagger's regex path mints cve-tagged blog mentions with neither
    // a severity nor a score — every child of the header row is optional.
    await _rowHeight(tester, _article(tags: ['cve']));
    expect(tester.takeException(), isNull);
  });
}
