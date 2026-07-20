import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Bundled font families (declared in pubspec.yaml `fonts:`). Referenced by
/// name so a typo can't silently fall back to the platform font. Sans ships
/// 400/500/700; Mono ships 400/600 — the only weights the app uses.
const kFontSans = 'IBM Plex Sans';
const kFontMono = 'IBM Plex Mono';

const kRed = Color(0xFFEE0000);
const kBg = Color(0xFF0D0D0D);
const kSurface = Color(0xFF1A1A1A);
const kSurface2 = Color(0xFF242424);
const kBorder = Color(0xFF2A2A2A);
const kTextPrimary = Color(0xFFFFFFFF);
const kTextSecondary = Color(0xFF888888);
const kTextMuted = Color(0xFF555555);
const kStatusGreen = Color(0xFF00FF88);

const kLightBg = Color(0xFFFFFFFF);
const kLightSurface = Color(0xFFF5F5F5);
const kLightSurface2 = Color(0xFFEEEEEE);
const kLightBorder = Color(0xFFE0E0E0);
const kLightTextPrimary = Color(0xFF0D0D0D);
const kLightTextSecondary = Color(0xFF555555);
const kLightTextMuted = Color(0xFF999999);

bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color bgOf(BuildContext context) => isDark(context) ? kBg : kLightBg;
Color surfaceOf(BuildContext context) =>
    isDark(context) ? kSurface : kLightSurface;
Color surface2Of(BuildContext context) =>
    isDark(context) ? kSurface2 : kLightSurface2;
Color borderOf(BuildContext context) =>
    isDark(context) ? kBorder : kLightBorder;
Color textPrimaryOf(BuildContext context) =>
    isDark(context) ? kTextPrimary : kLightTextPrimary;
Color textSecondaryOf(BuildContext context) =>
    isDark(context) ? kTextSecondary : kLightTextSecondary;
Color textMutedOf(BuildContext context) =>
    isDark(context) ? kTextMuted : kLightTextMuted;

/// Luminance above which text on an accent fill must be black, not white.
///
/// **This is 0.40 and not the conventional 0.5 on purpose.** The severity
/// amber (`#FFAA00`, [CveSeverity.medium]) measures 0.5001 — a 0.5 rule
/// decides it by a margin of 0.0001, so any palette tweak or rounding
/// change silently flips it to white text at a 1.91:1 contrast ratio
/// (illegible; worse than no styling at all). 0.40 clears the brightest
/// accent we actually use below it (`#FF6600`, 0.3076) by ~0.09 and amber
/// by ~0.10, so nothing sits near the boundary.
///
/// Every color the feed's filter pills pass as `selectedColor` — kRed
/// 0.1818, `#00AA44` 0.2917, `#FF6600` 0.3076 — falls below this, so they
/// all resolve to white and render exactly as they did before [onAccent]
/// existed. `test/filter_pill_test.dart` pins that.
const double kAccentLuminanceThreshold = 0.40;

/// Readable foreground for text sitting on a solid [accent] fill.
///
/// Material's `colorScheme.onSurface` doesn't cover this: it maps the
/// theme's surface colors, not the arbitrary semantic accents (severity
/// red/orange/amber/grey, release green) these controls fill with.
Color onAccent(Color accent) =>
    accent.computeLuminance() > kAccentLuminanceThreshold
        ? Colors.black
        : Colors.white;

/// Named text styles that aren't part of the Material [TextTheme].
class AppTextStyles {
  AppTextStyles._();

  /// Canonical monospace style for technical values — version numbers, CVE ids,
  /// the RevenueCat id. Deliberately sets **no color** so it inherits the
  /// ambient `DefaultTextStyle`/`TextTheme` color and works in both light and
  /// dark; call sites `.copyWith(color: ...)` when they need a specific one.
  static const TextStyle technicalLabel = TextStyle(
    fontFamily: kFontMono,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  /// Canonical uppercase screen/route title — the AppBar title on screens
  /// pushed as routes (e.g. "CVE ALERTS", "OCP VERSIONS"). Color is inherited
  /// from the ambient AppBar `titleTextStyle` so it stays theme-correct in
  /// light and dark, same color-agnostic pattern as [technicalLabel].
  static const TextStyle screenTitle = TextStyle(
    fontFamily: kFontSans,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 2,
  );

  /// Uppercase tracked mini-header that labels a body section (e.g. "SOURCES",
  /// "TOP STORIES"). Muted color is theme-aware so it can't live in a const —
  /// call sites add `.copyWith(color: textMutedOf(context))`.
  static const TextStyle sectionLabel = TextStyle(
    fontFamily: kFontSans,
    fontSize: 10,
    letterSpacing: 2,
  );

  /// Small muted metadata line (timestamps, counts, hints). Same theme-aware
  /// color rule as [sectionLabel] — call sites supply the muted color via
  /// `.copyWith(color: ...)`.
  static const TextStyle caption = TextStyle(
    fontFamily: kFontSans,
    fontSize: 11,
  );
}

ThemeData appTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kBg,
  colorScheme: const ColorScheme.dark(
    primary: kRed,
    surface: kSurface,
  ),
  cardColor: kSurface,
  dividerColor: kBorder,
  textTheme: ThemeData.dark().textTheme.apply(fontFamily: kFontSans),
  appBarTheme: AppBarTheme(
    backgroundColor: kBg,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: const TextStyle(
      fontFamily: kFontSans,
      color: kTextPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.0,
    ),
    iconTheme: const IconThemeData(color: kTextSecondary),
    systemOverlayStyle: SystemUiOverlayStyle.light,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: kSurface2,
    labelStyle: const TextStyle(
      color: kTextSecondary,
      fontSize: 11,
      letterSpacing: 1.0,
      fontWeight: FontWeight.w600,
    ),
    side: const BorderSide(color: kBorder),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    ),
  ),
);

ThemeData lightTheme() => ThemeData(
  brightness: Brightness.light,
  scaffoldBackgroundColor: kLightBg,
  colorScheme: const ColorScheme.light(
    primary: kRed,
    surface: kLightSurface,
  ),
  cardColor: kLightSurface,
  dividerColor: kLightBorder,
  textTheme: ThemeData.light().textTheme.apply(fontFamily: kFontSans),
  appBarTheme: AppBarTheme(
    backgroundColor: kLightBg,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: const TextStyle(
      fontFamily: kFontSans,
      color: kLightTextPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.0,
    ),
    iconTheme: const IconThemeData(color: kLightTextSecondary),
    systemOverlayStyle: SystemUiOverlayStyle.dark,
  ),
  chipTheme: ChipThemeData(
    backgroundColor: kLightSurface2,
    labelStyle: const TextStyle(
      color: kLightTextSecondary,
      fontSize: 11,
      letterSpacing: 1.0,
      fontWeight: FontWeight.w600,
    ),
    side: const BorderSide(color: kLightBorder),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
    ),
  ),
);
