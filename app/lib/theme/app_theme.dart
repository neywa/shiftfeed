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
