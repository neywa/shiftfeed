// Regression tests for the bottom-nav tab wiring.
//
// The failure mode these exist for is SILENT. The nav was four tabs with
// bare integer indices; inserting the CVE tab at position 2 shifted Saved
// 2->3 and Settings 3->4. A missed shift produces no crash and no analyzer
// error — `_bottomNavIndex == 2` still compiles, it just now means "CVEs"
// while claiming to mean "Saved", so the Saved swipe hint silently fires
// on the wrong tab. The `i > 3` bounds guard likewise kept compiling while
// routing the real Settings tab to a "Coming soon" snackbar.
//
// NavTab exists to make that class of bug unrepresentable. These tests
// pin the two things it can't enforce on its own: the tab ORDER, and its
// alignment with the IndexedStack children in home_screen.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiftfeed/screens/nav_tabs.dart';

void main() {
  group('tab order', () {
    test('is Feed / Versions / CVEs / Saved / Settings', () {
      // Position is the whole contract — IndexedStack indexes its children
      // by it. Reordering this enum without reordering those children
      // silently swaps two screens.
      expect(NavTab.values, [
        NavTab.feed,
        NavTab.versions,
        NavTab.cves,
        NavTab.saved,
        NavTab.settings,
      ]);
    });

    test('each tab maps to its expected index', () {
      expect(NavTab.feed.index, 0);
      expect(NavTab.versions.index, 1);
      expect(NavTab.cves.index, 2, reason: 'CVE tab is the centre of five');
      expect(NavTab.saved.index, 3, reason: 'shifted from 2 by the CVE insert');
      expect(
        NavTab.settings.index,
        4,
        reason: 'shifted from 3 by the CVE insert',
      );
    });
  });

  group('bounds guard', () {
    test('accepts every real tab index', () {
      // The bug: a stale `i > 3` guard rejects Settings at 4 and shows
      // "Coming soon" instead of the tab.
      for (final tab in NavTab.values) {
        expect(NavTab.isValidIndex(tab.index), isTrue, reason: tab.label);
      }
    });

    test('rejects out-of-range indices', () {
      expect(NavTab.isValidIndex(-1), isFalse);
      expect(NavTab.isValidIndex(NavTab.values.length), isFalse);
      expect(NavTab.isValidIndex(99), isFalse);
    });

    test('tracks the tab count rather than a literal', () {
      expect(NavTab.isValidIndex(4), isTrue);
      expect(NavTab.values.length, 5);
    });
  });

  group('bottomNavItems', () {
    test('renders one item per tab, in enum order', () {
      final items = bottomNavItems;
      expect(items.length, NavTab.values.length);
      expect(
        items.map((i) => i.label).toList(),
        ['Feed', 'Versions', 'CVEs', 'Saved', 'Settings'],
      );
    });
  });

  group('home_screen IndexedStack alignment', () {
    // The one invariant NavTab can't enforce in the type system: the
    // IndexedStack children are positional widget literals, so nothing
    // stops someone inserting a screen there without touching NavTab (or
    // vice versa). Rather than stand up a full HomeScreen — which needs a
    // live Supabase singleton and would test the mocks more than the
    // wiring — assert against the source text.
    late final String source;

    /// Just the mobile nav region — the IndexedStack plus the
    /// BottomNavigationBar's onTap. Scoped because the rest of the file
    /// legitimately contains both `BookmarksScreen(` / `SettingsScreen(`
    /// (the desktop push-routes, which are separate route-pushing code,
    /// not the IndexedStack) and unrelated `i > 0` loop guards.
    late final String navSource;

    setUpAll(() {
      source = File('lib/screens/home_screen.dart').readAsStringSync();
      final start = source.indexOf('IndexedStack(');
      final end = source.indexOf('PreferredSizeWidget _buildMobileAppBar');
      expect(start, greaterThan(-1), reason: 'IndexedStack not found');
      expect(end, greaterThan(start), reason: '_buildMobileAppBar not found');
      navSource = source.substring(start, end);
    });

    test('declares its per-tab isActive checks via NavTab, not literals', () {
      // These two drive real behaviour (Versions self-heal refetch, Saved
      // swipe-hint replay) and are exactly what broke silently before.
      expect(source, contains('_bottomNavIndex == NavTab.versions.index'));
      expect(source, contains('_bottomNavIndex == NavTab.cves.index'));
      expect(source, contains('_bottomNavIndex == NavTab.saved.index'));
      expect(source, contains('_bottomNavIndex == NavTab.feed.index'));
    });

    test('no bare integer comparison against _bottomNavIndex survives', () {
      // The regression guard: any `_bottomNavIndex == 2` reintroduces a
      // number that a future tab insert has to remember to shift.
      final bareCompare = RegExp(r'_bottomNavIndex\s*==\s*\d');
      expect(
        bareCompare.hasMatch(source),
        isFalse,
        reason: 'compare to NavTab.<tab>.index instead of an integer literal',
      );
    });

    test('IndexedStack children are ordered to match NavTab', () {
      // Screens appear in the stack in enum order. Feed is an inline
      // RefreshIndicator rather than a named screen, so anchor on the
      // four named ones.
      final order = [
        'VersionsScreen(',
        'CveScreen(',
        'BookmarksScreen(',
        'SettingsScreen(',
      ];
      final positions = [
        for (final name in order) navSource.indexOf(name),
      ];
      for (var i = 0; i < order.length; i++) {
        expect(positions[i], greaterThan(-1), reason: '${order[i]} missing');
      }
      final sorted = [...positions]..sort();
      expect(
        positions,
        sorted,
        reason: 'IndexedStack children are out of order vs NavTab.values',
      );
    });

    test('the bounds guard is derived, not hardcoded', () {
      expect(navSource, contains('NavTab.isValidIndex(i)'));
      expect(
        RegExp(r'i\s*>\s*\d').hasMatch(navSource),
        isFalse,
        reason: 'a literal upper bound goes stale on the next tab insert',
      );
    });
  });
}
