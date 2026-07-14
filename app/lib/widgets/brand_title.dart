import 'package:flutter/material.dart';

import '../services/entitlement_service.dart';
import '../theme/app_theme.dart';
import '../theme/text_metrics.dart';

/// Font size of the wordmark. The vertical [ProBadge] is sized off this so
/// the two stay in step if the title is ever resized.
const double _kWordmarkSize = 22;

/// The "ShiftFeed" wordmark shown in the upper-left of every bottom-nav
/// tab's AppBar, with the [ProBadge] appended when the user is Pro.
///
/// Resolves its own entitlement state and listens to [EntitlementService]
/// so the badge appears/disappears on sign-in, purchase, restore, and the
/// debug-only Pro override — no per-screen plumbing.
class BrandTitle extends StatefulWidget {
  /// Long-press handler on the wordmark. The feed passes the debug-only
  /// dev-Pro toggle here; everywhere else this is null and the gesture is
  /// a no-op.
  final VoidCallback? onLongPress;

  const BrandTitle({super.key, this.onLongPress});

  @override
  State<BrandTitle> createState() => _BrandTitleState();
}

class _BrandTitleState extends State<BrandTitle> {
  bool _isPro = false;

  @override
  void initState() {
    super.initState();
    _refreshPro();
    EntitlementService.instance.addListener(_refreshPro);
  }

  @override
  void dispose() {
    EntitlementService.instance.removeListener(_refreshPro);
    super.dispose();
  }

  Future<void> _refreshPro() async {
    final isPro = await EntitlementService.instance.isPro();
    if (!mounted || isPro == _isPro) return;
    setState(() => _isPro = isPro);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible + ellipsis so the title yields width to the PRO
          // badge on narrow AppBar layouts instead of overflowing.
          Flexible(
            child: Text(
              'ShiftFeed',
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: textPrimaryOf(context),
                fontSize: _kWordmarkSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
          if (_isPro) ...[
            // A vertical tab sits closer to the word than the old pill did.
            const SizedBox(width: 6),
            // The wordmark sets no explicit `height`, so its Text box is the
            // font's natural line box — match it exactly and the badge costs
            // the title row no extra height.
            const ProBadge.vertical(height: kFontBox * _kWordmarkSize),
          ],
        ],
      ),
    );
  }
}

/// Tiny red "PRO" pill rendered where [EntitlementService.isPro] is true
/// (including the debug-only override toggled by long-pressing the title).
///
/// Two forms: a horizontal pill next to a section title, and a rotated
/// [ProBadge.vertical] beside the wordmarks, which reads bottom-to-top and
/// costs a third of the width the horizontal one did.
class ProBadge extends StatelessWidget {
  /// Horizontal pill — used beside a Settings section title.
  const ProBadge({super.key}) : height = null;

  /// Pill rotated a quarter turn anticlockwise, so it reads bottom-to-top
  /// with the P at the bottom. [height] is the whole badge: pass the
  /// neighbouring text's box height and the badge costs its row nothing.
  const ProBadge.vertical({super.key, required double this.height});

  /// Null for the horizontal form, which sizes itself to its text.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final h = height;
    final pill = Container(
      // Rotated, the horizontal padding runs along the tight axis: the pill
      // is laid out to a tight width of `h`, and "PRO" alone wants ~21 of it.
      padding: EdgeInsets.symmetric(horizontal: h == null ? 6 : 3, vertical: 2),
      decoration: BoxDecoration(
        color: kRed,
        borderRadius: BorderRadius.circular(h == null ? 4 : 3),
      ),
      child: const FittedBox(
        // A no-op at the natural size; it exists so OS text scaling shrinks
        // the label instead of overflowing the pill.
        fit: BoxFit.scaleDown,
        child: Text(
          'PRO',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
    if (h == null) return pill;
    // quarterTurns counts *clockwise* turns, so 3 is the anticlockwise one
    // that lands the leading glyph at the bottom. RotatedBox swaps its
    // child's constraints: the SizedBox's height becomes the pill's width.
    return SizedBox(
      height: h,
      child: RotatedBox(quarterTurns: 3, child: pill),
    );
  }
}
