import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

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

ThemeData appTheme() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: kBg,
  colorScheme: const ColorScheme.dark(
    primary: kRed,
    surface: kSurface,
  ),
  cardColor: kSurface,
  dividerColor: kBorder,
  textTheme: GoogleFonts.ibmPlexSansTextTheme(
    ThemeData.dark().textTheme,
  ).copyWith(
    labelSmall: GoogleFonts.ibmPlexMono(
      color: kTextMuted,
      fontSize: 10,
      letterSpacing: 1.0,
    ),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: kBg,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: GoogleFonts.ibmPlexSans(
      color: kTextPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w800,
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
  textTheme: GoogleFonts.ibmPlexSansTextTheme(
    ThemeData.light().textTheme,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: kLightBg,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: GoogleFonts.ibmPlexSans(
      color: kLightTextPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w800,
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
