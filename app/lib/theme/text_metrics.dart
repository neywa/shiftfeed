/// Optical spacing helpers for IBM Plex Sans (bundled; see pubspec `fonts:`).
///
/// A [Text]'s line box carries a blank strip above its glyphs and another
/// below its baseline, so laying out to the *boxes* leaves gaps that look
/// bigger than the number you wrote. Spacing that reads correctly is measured
/// to the glyphs: take the nominal gap and subtract the strips of whatever
/// sits on either side of it.
///
/// The per-em figures were measured off a device screenshot rather than
/// derived from the font's nominal metrics — as rendered, the visible top is
/// the ascender (~0.73em, not the 0.698em cap height) and the descent runs
/// deeper than nominal; deriving them from the published numbers was wrong by
/// up to 0.9dp.
library;

/// The font's natural line box, as a multiple of the font size.
const double kFontBox = 1.3;

/// Ascent -> first glyph row, per em.
const double kInkTopEm = 0.292;

/// Baseline -> box bottom, per em.
const double kInkBottomEm = 0.32;

/// Blank strip inside a [Text]'s line box, above its glyphs.
///
/// [height] is the style's line-height multiplier; its extra leading splits
/// evenly top and bottom, so every [Text] measured with these helpers must set
/// `leadingDistribution: TextLeadingDistribution.even`. Only valid for text
/// that sets an explicit `height` — without one, Flutter uses the font's own
/// line metrics (which carry a leading the multiplier would replace) and the
/// strips have to be measured directly instead.
double inkTop(double size, double height) =>
    (height - kFontBox) * size / 2 + kInkTopEm * size;

/// Blank strip inside a [Text]'s line box, below its baseline.
double inkBottom(double size, double height) =>
    (height - kFontBox) * size / 2 + kInkBottomEm * size;
