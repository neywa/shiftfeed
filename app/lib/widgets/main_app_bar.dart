import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/digest_screen.dart';
import '../services/entitlement_service.dart';
import '../theme/app_theme.dart';
import '../theme/layout_notifier.dart';
import '../theme/theme_notifier.dart';
import 'brand_title.dart';
import 'paywall_sheet.dart';

/// The app bar shared by all four bottom-nav tabs: the ShiftFeed wordmark,
/// the same four actions in the same order, and the red rule underneath.
///
/// Actions that have nothing to act on for a given screen are greyed out
/// rather than dropped, so the bar's shape never shifts between tabs:
/// [onSearch] is null everywhere except the feed, and [viewToggleEnabled]
/// is true only where a card list responds to it (feed and Saved).
class MainAppBar extends StatelessWidget implements PreferredSizeWidget {
  /// Opens the screen's search UI. Null greys the search icon out.
  final VoidCallback? onSearch;

  /// Whether this screen renders [ArticleCard]s that honour [LayoutNotifier].
  /// False greys the view-mode icon out.
  final bool viewToggleEnabled;

  /// Long-press on the wordmark — the feed passes its debug-only dev-Pro
  /// toggle here.
  final VoidCallback? onBrandLongPress;

  /// Screen-specific actions placed ahead of the shared four (the Saved
  /// screen's sync indicator).
  final List<Widget> leadingActions;

  /// Extra row under the red rule — the feed's filter chips.
  final Widget? bottom;

  /// Height of [bottom], including its own padding. Must be supplied by the
  /// caller: preferredSize is read before [bottom] is ever laid out.
  final double bottomHeight;

  const MainAppBar({
    super.key,
    this.onSearch,
    this.viewToggleEnabled = false,
    this.onBrandLongPress,
    this.leadingActions = const [],
    this.bottom,
    this.bottomHeight = 0,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + 1 + bottomHeight); // +1 = the red rule

  @override
  Widget build(BuildContext context) {
    final viewMode = context.watch<LayoutNotifier>().mode;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      title: BrandTitle(onLongPress: onBrandLongPress),
      actions: [
        ...leadingActions,
        _action(
          context,
          icon: Icons.search,
          tooltip: 'Search',
          onPressed: onSearch,
        ),
        _action(
          context,
          icon: viewMode == ViewMode.grid
              ? Icons.view_list_rounded
              : Icons.grid_view_rounded,
          tooltip: 'View mode',
          onPressed: viewToggleEnabled
              ? () {
                  final notifier = context.read<LayoutNotifier>();
                  notifier.setMode(
                    notifier.mode == ViewMode.grid
                        ? ViewMode.list
                        : ViewMode.grid,
                  );
                }
              : null,
        ),
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.auto_awesome,
                size: 20,
                color: textSecondaryOf(context),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          onPressed: () => openDigest(context),
          tooltip: 'AI Briefing',
        ),
        Consumer<ThemeNotifier>(
          builder: (context, notifier, _) => IconButton(
            icon: Icon(
              notifier.isDark ? Icons.light_mode : Icons.dark_mode,
              size: 20,
              color: textSecondaryOf(context),
            ),
            onPressed: notifier.toggle,
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(1 + bottomHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(height: 1, color: kRed),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }

  /// A shared action whose disabled state is drawn explicitly: IconButton
  /// only falls back to the theme's disabled colour when the Icon carries no
  /// colour of its own, and these all do.
  Widget _action(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    return IconButton(
      icon: Icon(
        icon,
        size: 20,
        color: enabled
            ? textSecondaryOf(context)
            : textMutedOf(context).withValues(alpha: 0.4),
      ),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

/// Opens the daily AI briefing, or the paywall for non-Pro users.
///
/// Web is exempt: there is no functional paywall there and Pro is
/// unattainable, and the curated briefing is otherwise free content.
Future<void> openDigest(BuildContext context) async {
  final isPro = await EntitlementService.instance.isPro();
  if (!context.mounted) return;
  if (!isPro && !kIsWeb) {
    await PaywallSheet.show(context, reason: PaywallReason.briefing);
    return;
  }
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const DigestScreen()),
  );
}
