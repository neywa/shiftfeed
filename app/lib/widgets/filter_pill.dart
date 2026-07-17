import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The app's canonical selection pill — the feed's source/tag filter row
/// and the CVE screen's severity filter.
///
/// Extracted from `HomeScreen._mobileChip` so the two screens can't drift
/// apart again. They already had: the CVE screen shipped a bespoke chip
/// with a transparent fill and `kTextMuted` text, which in dark mode is a
/// 2.61:1 contrast ratio against the background — under WCAG's 4.5:1 for
/// text and even its 3:1 for UI. The shape here (a `surface2` body, so
/// the pill reads as an object, plus `textSecondary` at 4.38:1) is the
/// feed's, and is what makes it legible.
///
/// Selected renders as a solid [selectedColor] fill with an [onAccent]
/// foreground. Unselected keeps its body and a border.
class FilterPill extends StatelessWidget {
  /// Nominal type size. Exposed because the app bar has to reserve the
  /// pill's height before the pill is laid out — see [heightOf].
  static const double fontSize = 11;

  /// Vertical padding inside the pill, per side.
  static const double verticalPadding = 6;

  /// Matches the info cards' corner radius (the CVE rows, the version
  /// cards, the submit form all use 6) so the controls sit in the same
  /// visual language as the content they filter. Was 20 — a true pill —
  /// which read as a different design system from the cards below it.
  ///
  /// Note this is now the same radius as `ToggleButton`. The two are no
  /// longer told apart by shape, only by size (the toggle is taller, with
  /// 12px type) and by their SORT / FILTER row labels.
  static const double _radius = 6;

  static const TextStyle _labelStyle = TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
  );

  /// The pill's natural height at the current text scale.
  ///
  /// `MainAppBar.bottomHeight` must be >= this or the app bar's bottom
  /// overflows. The feed hosts this pill in that slot, and the metrics
  /// driving the number live here rather than at the call site — a caller
  /// hand-deriving it from a font size this widget owns is how it goes
  /// stale.
  ///
  /// **Measured, not computed from a nominal line-height multiplier.**
  /// The old call-site formula guessed `fontSize * 1.3 + padding` = 26.3
  /// while the pill actually renders at 28.0, so the app bar had been
  /// under-reserving by 1.7dp. There is no multiplier that predicts it
  /// (see CLAUDE.md, "Spacing is optical"): the line box comes from the
  /// resolved font's ascent/descent plus whatever `height` the ambient
  /// [DefaultTextStyle] contributes. A TextPainter asks the font.
  ///
  /// Measures the same MERGED style the [Text] below will resolve to —
  /// `_labelStyle` alone is not what renders, because `Text` merges it
  /// over `DefaultTextStyle` (which is where the theme's IBM Plex Sans
  /// and its line-height multiplier come from). Painting the bare style
  /// under-reports by ~5dp.
  static double heightOf(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'X',
        style: DefaultTextStyle.of(context).style.merge(_labelStyle),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.height + verticalPadding * 2;
  }

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Fill when selected. Defaults to [kRed]; pass a semantic color for
  /// chips that carry meaning (release green, severity red/amber/…).
  final Color? selectedColor;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = selectedColor ?? kRed;
    return Material(
      color: selected ? activeColor : surface2Of(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: BorderSide(
          color: selected ? Colors.transparent : borderOf(context),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_radius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: verticalPadding,
          ),
          child: Text(
            label,
            // Must stay in sync with [_labelStyle], which [heightOf]
            // measures — only the color varies with selection.
            style: _labelStyle.copyWith(
              // Not a hardcoded white: the severity amber would render at
              // 1.91:1 against it. See [kAccentLuminanceThreshold].
              color: selected ? onAccent(activeColor) : textSecondaryOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
