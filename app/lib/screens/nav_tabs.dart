import 'package:flutter/material.dart';

/// The mobile bottom-nav tabs, in display order.
///
/// This enum is the single source of truth for tab positions, and it
/// exists specifically to kill a bug class. The nav used to be four
/// hardcoded `BottomNavigationBarItem`s indexed by bare integers, with
/// `_bottomNavIndex == 2` scattered through `home_screen.dart` to drive
/// per-tab behaviour (the Versions self-heal refetch, the Saved swipe
/// hint) and a `i > 3` bounds guard. Inserting a tab meant hand-shifting
/// every one of those numbers, and missing one FAILS SILENTLY: no crash,
/// no analyzer warning — the swipe hint just quietly fires on the wrong
/// tab, or a real tab routes to the "Coming soon" snackbar.
///
/// So: never compare `_bottomNavIndex` to an integer literal. Compare to
/// `NavTab.saved.index`, and derive the bounds guard from
/// `NavTab.values.length`. Reordering this enum then moves everything at
/// once, and [bottomNavItems] can't drift out of alignment with the
/// `IndexedStack` children because both are ordered by this declaration.
///
/// The one invariant a reader must uphold by hand: the `IndexedStack`
/// children in `home_screen.dart` must stay in this same order. That's
/// pinned by `test/nav_tabs_test.dart`.
enum NavTab {
  feed(icon: Icons.rss_feed, label: 'Feed'),
  versions(icon: Icons.terminal, label: 'Versions'),
  cves(icon: Icons.shield, label: 'CVEs'),
  saved(icon: Icons.bookmark_outline, label: 'Saved'),
  settings(icon: Icons.settings, label: 'Settings');

  final IconData icon;
  final String label;

  const NavTab({required this.icon, required this.label});

  /// True when [i] is a selectable tab position. The old hand-maintained
  /// `i > 3` literal is what this replaces.
  static bool isValidIndex(int i) => i >= 0 && i < NavTab.values.length;
}

/// The bar's items, ordered by [NavTab]'s declaration.
List<BottomNavigationBarItem> get bottomNavItems => [
      for (final tab in NavTab.values)
        BottomNavigationBarItem(icon: Icon(tab.icon), label: tab.label),
    ];
