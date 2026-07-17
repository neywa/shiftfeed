import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'filter_pill.dart';

/// The app's canonical single-select toggle — the feed's desktop
/// "Latest / Top" control and the CVE screen's sort control.
///
/// Extracted from `HomeScreen._feedToggleButton`.
///
/// Shares its 6dp radius with [FilterPill], which was squared off from 20
/// to match the info cards. In [dense] mode it also shares the pill's
/// height, leaving the SORT / FILTER row labels and the fill colors as
/// the only cues that one row is single-select and the other multi.
class ToggleButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Fill when selected. Defaults to [kRed].
  final Color? selectedColor;

  /// Match [FilterPill]'s height exactly, for rows that sit directly
  /// above or beside a pill row (the CVE screen's sort control).
  ///
  /// Off by default because the feed's desktop "Latest / Top" toggle
  /// stands alone and keeps Material's full-size button.
  final bool dense;

  const ToggleButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedColor,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = selectedColor ?? kRed;

    // Height is PINNED to the pill's rather than reverse-engineered from
    // padding, so the two match at any text scale and can't drift if
    // either widget's type changes. Two things fight this and both have
    // to be disabled: FilledButton's default 48dp minimum size, and
    // MaterialTapTargetSize.padded, which pads the *hit area* out to 48
    // and grows the laid-out box with it. Left as-is, a dense button
    // measures 48 next to a 28 pill.
    final height = dense ? FilterPill.heightOf(context) : null;

    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: selected ? activeColor : surface2Of(context),
        foregroundColor:
            selected ? onAccent(activeColor) : textSecondaryOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: dense ? 0 : 10,
        ),
        minimumSize: dense ? Size(0, height!) : null,
        maximumSize: dense ? Size(double.infinity, height!) : null,
        tapTargetSize: dense ? MaterialTapTargetSize.shrinkWrap : null,
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
      child: Text(label.toUpperCase()),
    );
  }
}
