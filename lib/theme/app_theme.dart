import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // 1. Core Brand Colors
  static const Color electricBlue = Color(0xFF3867FF); // Primary buttons, links
  static const Color vividViolet = Color(0xFF853CFF); // Secondary actions, active audio
  static const Color neonCyan = Color(0xFF06D6F0); // Waveforms, progress, accents
  static const Color vibrantMagenta = Color(0xFFF02CC8); // Highlights, peaks, gradients

  // Aliases for compatibility
  static const Color primary = electricBlue;
  static const Color secondary = vividViolet;
  static const Color accent = neonCyan;
  static const Color highlight = vibrantMagenta;
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color errorRed = Color(0xFFEF4444);

  // 2. White-theme UI Colors
  static const Color mainBackground = Color(0xFFFFFFFF);
  static const Color secondaryBackground = Color(0xFFF7F8FC);
  static const Color cardBackground = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE7EAF2);
  static const Color primaryText = Color(0xFF111827);
  static const Color secondaryText = Color(0xFF64748B);
  static const Color disabledControl = Color(0xFFCBD5E1);

  // Compatibility Aliases
  static const Color surfaceLight = secondaryBackground;
  static const Color surface = cardBackground;
  static const Color background = mainBackground;
  static const Color cardColor = cardBackground;
  static const Color coral = errorRed;
  static const Color amber = Color(0xFFF59E0B);
  static const LinearGradient primaryGradient = sentraGradient;
  static const LinearGradient accentGradient = blueVioletGradient;

  // 3. Multi-Song Timeline & Sequence Color Palette (Distinct non-blue colors to avoid UI confusion)
  static const List<Color> songPalette = [
    Color(0xFFFF5722), // Coral Flame / Deep Orange
    Color(0xFF10B981), // Emerald Green
    Color(0xFF8B5CF6), // Royal Violet
    Color(0xFFEC4899), // Hot Pink
    Color(0xFFF59E0B), // Golden Amber
    Color(0xFFEF4444), // Crimson Red
    Color(0xFF84CC16), // Lime Green
    Color(0xFFFF7A59), // Sunset Salmon
    Color(0xFF9333EA), // Deep Orchid / Purple
  ];



  // 3. Signature Sentra Gradient (Cyan → Blue → Violet → Magenta)
  static const LinearGradient sentraGradient = LinearGradient(
    colors: [
      Color(0xFF06D6F0), // Cyan
      Color(0xFF3867FF), // Blue
      Color(0xFF853CFF), // Violet
      Color(0xFFF02CC8), // Magenta
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient blueVioletGradient = LinearGradient(
    colors: [
      Color(0xFF3867FF),
      Color(0xFF853CFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient whatsappGradient = LinearGradient(
    colors: [Color(0xFF25D366), Color(0xFF128C7E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get whiteTheme {
    final baseTextTheme = GoogleFonts.outfitTextTheme(ThemeData.light().textTheme);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: mainBackground,
      primaryColor: electricBlue,
      colorScheme: const ColorScheme.light(
        primary: electricBlue,
        secondary: vividViolet,
        surface: cardBackground,
        error: errorRed,
        onPrimary: Colors.white,
        onSurface: primaryText,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
        },
      ),
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1.2),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: mainBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: primaryText),
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: primaryText,
          letterSpacing: 0.3,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondaryBackground,
        hintStyle: GoogleFonts.outfit(color: secondaryText.withValues(alpha: 0.6), fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: electricBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: electricBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: electricBlue,
        inactiveTrackColor: border,
        thumbColor: electricBlue,
        overlayColor: electricBlue.withValues(alpha: 0.15),
        trackHeight: 4,
        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
      ),
      textTheme: baseTextTheme.copyWith(
        titleLarge: GoogleFonts.outfit(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: primaryText,
        ),
        titleMedium: GoogleFonts.outfit(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: primaryText,
        ),
        bodyLarge: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: primaryText,
        ),
        bodyMedium: GoogleFonts.outfit(
          fontSize: 13,
          color: secondaryText,
        ),
      ),
    );
  }

  static ThemeData get darkTheme => whiteTheme;
}

