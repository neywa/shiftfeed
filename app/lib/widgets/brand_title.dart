import 'package:flutter/material.dart';

import '../services/entitlement_service.dart';
import '../theme/app_theme.dart';

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
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
          if (_isPro) ...[
            const SizedBox(width: 8),
            const ProBadge(),
          ],
        ],
      ),
    );
  }
}

/// Tiny red "PRO" pill rendered next to the app title when
/// [EntitlementService.isPro] is true (including the debug-only
/// override toggled by long-pressing the title).
class ProBadge extends StatelessWidget {
  const ProBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: kRed,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
