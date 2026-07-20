import 'package:flutter/material.dart';

import '../services/entitlement_service.dart';
import '../theme/app_theme.dart';

/// Font size of the wordmark. The vertical [ProBadge] is sized off this so
/// the two stay in step if the title is ever resized.
const double _kWordmarkSize = 22;

/// Tightened tracking on the wordmark, expressed per-em so it scales with the
/// font size. -1.45px at size 22 reproduces the Figma design width (which used
/// per-glyph kerning Flutter can't express); other sizes stay proportional.
const double _kWordmarkTrackingEm = -1.45 / 22;

/// Letter spacing (logical px) for a wordmark rendered at [fontSize].
double wordmarkTrackingFor(double fontSize) =>
    _kWordmarkTrackingEm * fontSize;

/// Gap between the wordmark and the vertical [ProBadge].
const double _kBadgeGap = 3;

/// The wordmark is set in two halves: "Shift" upright, "FEED" italic (caps) —
/// both Bold (w700, inherited from the base style). The italic half needs IBM
/// Plex Sans Bold Italic bundled (see pubspec.yaml); without it Flutter
/// would synthesize a skewed faux-italic.
const String _kWordmarkUpright = 'Shift';
const String _kWordmarkItalic = 'FEED';

/// Shrunk PRO badge geometry (from the Figma design): a compact vertical
/// pill, decoupled from the wordmark line box it used to match.
const double _kBadgeLongAxis = 21; // reads bottom-to-top; the rotated height
const double _kBadgeThickness = 9; // the rotated width
const double _kBadgeRadius = 1;

/// The "ShiftFeed" wordmark type — "Shift" upright, "Feed" italic, both Bold
/// (w700) IBM Plex Sans. Shared by the mobile [BrandTitle] and the desktop
/// sidebar so the two never drift: the italic split lives here once, and the
/// tracking scales with [fontSize] via [wordmarkTrackingFor].
///
/// Wrap in a [Flexible] at the call site so it yields width to a trailing
/// [ProBadge] instead of overflowing.
class WordmarkText extends StatelessWidget {
  const WordmarkText({
    super.key,
    required this.fontSize,
    required this.color,
  });

  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      const TextSpan(
        children: [
          TextSpan(text: _kWordmarkUpright),
          TextSpan(
            text: _kWordmarkItalic,
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        ],
      ),
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontFamily: kFontSans,
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: wordmarkTrackingFor(fontSize),
      ),
    );
  }
}

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
            child: WordmarkText(
              fontSize: _kWordmarkSize,
              color: textPrimaryOf(context),
            ),
          ),
          if (_isPro) ...[
            // A vertical tab sits closer to the word than the old pill did.
            const SizedBox(width: _kBadgeGap),
            // Compact badge, shorter than the wordmark line box; the Row
            // centre-aligns it, so it costs the title row no extra height.
            const ProBadge.vertical(
              height: _kBadgeLongAxis,
              thickness: _kBadgeThickness,
              cornerRadius: _kBadgeRadius,
            ),
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
  const ProBadge({super.key})
      : height = null,
        thickness = null,
        cornerRadius = 4;

  /// Pill rotated a quarter turn anticlockwise, so it reads bottom-to-top
  /// with the P at the bottom. [height] is the badge's long (rotated) axis.
  ///
  /// [thickness] is the short (rotated) axis: pass it to force a compact
  /// badge whose "PRO" is scaled to fit; leave it null to hug the text (the
  /// desktop sidebar's larger badge). [cornerRadius] rounds the pill.
  const ProBadge.vertical({
    super.key,
    required double this.height,
    this.thickness,
    this.cornerRadius = 3,
  });

  /// Null for the horizontal form, which sizes itself to its text.
  final double? height;

  /// Short-axis size of the vertical badge, or null to hug the text.
  final double? thickness;

  /// Pill corner radius.
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final h = height;
    // A forced thickness leaves little room, so the compact badge trims its
    // vertical padding and lets the FittedBox scale "PRO" to fit.
    final compact = h != null && thickness != null;
    final pill = Container(
      // Rotated, the horizontal padding runs along the tight axis. The compact
      // badge is small enough that any padding steals visibly from "PRO", so it
      // is trimmed to a hairline and the label is left to fill the pill.
      padding: EdgeInsets.symmetric(
        horizontal: h == null
            ? 6
            : compact
                ? 1
                : 3,
        vertical: compact ? 0 : 2,
      ),
      decoration: BoxDecoration(
        color: kRed,
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: FittedBox(
        // Scales "PRO" down to fit the pill — both under OS text scaling and
        // when the badge is given a tight compact size.
        fit: BoxFit.scaleDown,
        child: Text(
          'PRO',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            // Collapse the line box to the glyph height so the FittedBox
            // isn't forced to shrink "PRO" to fit the font's ascent/descent
            // leading — "PRO" is caps-only, so this doesn't clip anything.
            height: compact ? 1.0 : null,
            leadingDistribution:
                compact ? TextLeadingDistribution.even : null,
          ),
        ),
      ),
    );
    if (h == null) return pill;
    // quarterTurns counts *clockwise* turns, so 3 is the anticlockwise one
    // that lands the leading glyph at the bottom. RotatedBox swaps its
    // child's constraints: the SizedBox's height becomes the pill's width,
    // and (when set) its width becomes the pill's height.
    return SizedBox(
      width: thickness,
      height: h,
      child: RotatedBox(quarterTurns: 3, child: pill),
    );
  }
}
