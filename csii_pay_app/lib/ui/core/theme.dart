import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Backgrounds - Official BAScii Matte Onyx
  static const Color bgDeep = Color(0xFF0B0C0E);
  static const Color bgSurface = Color(0xFF131518);
  static const Color bgCard = Color(0xFF1A1D24);

  // BAScii Signature Palette
  static const Color basciiGold = Color(0xFFC89B27);       // Official BAScii Ochre Gold
  static const Color basciiGoldBright = Color(0xFFE2AE35); // Vibrant Ochre
  static const Color basciiGoldLight = Color(0xFFF3C766);  // Light Gold
  static const Color basciiGoldDark = Color(0xFF9E7615);   // Deep Bronze
  static const Color basciiBannerBg = Color(0xFFC89B27);   // Highlight Banner Gold

  // Brand Accents
  static const Color brandGold = Color(0xFFC89B27);
  static const Color brandPurple = Color(0xFFC89B27);      // Primary accent mapped to BAScii Gold
  static const Color brandViolet = Color(0xFFE2AE35);
  static const Color brandTeal = Color(0xFFD4AF37);
  static const Color brandCyan = Color(0xFFF3C766);

  // Tokens
  static const Color cspColor = Color(0xFFE2AE35);         // Service Points (CSP) = BAScii Ochre Gold
  static const Color bdpColor = Color(0xFFD4AF37);         // Character Points (BDP) = Royal Burnished Gold
  static const Color bdpBlackGold = Color(0xFF14120E);     // Deep Obsidian Slate
  static const Color bdpGoldAccent = Color(0xFFFFDF73);    // Shimmering Champagne Gold
  static const Color bdpBorderGold = Color(0xFFD4AF37);    // Brushed Metallic Gold Border

  // Status
  static const Color success = Color(0xFF00E676);
  static const Color warning = Color(0xFFFFB830);
  static const Color error = Color(0xFFFF4560);
  static const Color info = Color(0xFF00B4D8);

  // Text
  static const Color textPrimary = Color(0xFFECEFF8);
  static const Color textSecondary = Color(0xFF9DA6B8);
  static const Color textMuted = Color(0xFF5A6478);

  // Glass
  static const Color glassStroke = Color(0x24C89B27);
  static const Color glassFill = Color(0x0DC89B27);

  static const LinearGradient brandGradient = LinearGradient(
        colors: [basciiGoldBright, basciiGold],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const LinearGradient bgGradient = LinearGradient(
        colors: [bgDeep, Color(0xFF14161B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  // Service Points (CSP) Gradient - Radiant Warm Ochre
  static const LinearGradient cspGradient = LinearGradient(
        colors: [Color(0xFFF3C766), Color(0xFFC89B27)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // Character Points (BDP) Gradient - Ultra-Premium Black Gold (Obsidian & Burnished Champagne Gold)
  static const LinearGradient bdpGradient = LinearGradient(
        colors: [
          Color(0xFF2B2418), // Burnished deep bronze-charcoal
          Color(0xFF16130E), // Obsidian core
          Color(0xFF0C0B08), // Jet black base
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const LinearGradient basciiGoldGradient = LinearGradient(
        colors: [Color(0xFFE2AE35), Color(0xFFC89B27)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.bgDeep,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.basciiGold,
        secondary: AppColors.basciiGoldBright,
        surface: AppColors.bgSurface,
        error: AppColors.error,
      ),
      textTheme: GoogleFonts.outfitTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
          ),
          displayMedium: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
          headlineMedium: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          bodyLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
          bodySmall: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
          labelLarge: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassStroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.glassStroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.basciiGold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        labelStyle: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.outfit(color: AppColors.textMuted, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.basciiGold,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.outfit(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
    );
  }
}
