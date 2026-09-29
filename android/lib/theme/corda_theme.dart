import 'package:flutter/material.dart';

/// Clean & Minimalist macOS Sonoma Design System for Corda
/// Strictly NO glassmorphism (no artificial blurs, no specular glow).
/// Clean solid surfaces, 1px subtle borders, high contrast accessibility.
class CordaTheme {
  // Sonoma Neutrals & Surfaces
  static const Color canvasBg = Color(0xFF121418);
  static const Color surfaceCard = Color(0xFF1C1E24);
  static const Color surfaceCardHover = Color(0xFF242730);
  static const Color surfaceCardSelected = Color(0xFF2A2E3A);
  static const Color surfaceSubtle = Color(0xFF16181E);
  
  // Sonoma Borders
  static const Color borderSubtle = Color(0xFF282B34);
  static const Color borderStrong = Color(0xFF383C48);
  static const Color borderFocus = Color(0xFF0A84FF);

  // Apple Sonoma Accent Palette
  static const Color accentBlue = Color(0xFF0A84FF);
  static const Color mintGreen = Color(0xFF34C759);
  static const Color amberWarning = Color(0xFFFF9F0A);
  static const Color roseDanger = Color(0xFFFF453A);
  static const Color purpleAccent = Color(0xFFBF5AF2);

  // Sonoma Typography Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF8E95A5);
  static const Color textMuted = Color(0xFF5A6072);

  // Backward compatibility alias for legacy code
  static const Color aquaPrimary = accentBlue;
  static const Color aquaCyan = Color(0xFF64D2FF);
  static const Color obsidianBg = canvasBg;
  static const Color obsidianGlass = surfaceCard;
  static const Color obsidianGlassBorder = borderSubtle;

  static const LinearGradient aquaGradient = LinearGradient(
    colors: [accentBlue, Color(0xFF0071E3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardHeaderGradient = LinearGradient(
    colors: [Color(0xFF1C1E24), Color(0xFF16181E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Clean Sonoma Card Decoration (solid surface, 1px crisp border)
  static BoxDecoration sonomaCardDecoration({
    double borderRadius = 14,
    Color? borderColor,
    Color? fillColor,
    bool isSelected = false,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: fillColor ?? (isSelected ? surfaceCardSelected : surfaceCard),
      border: Border.all(
        color: borderColor ?? (isSelected ? accentBlue : borderSubtle),
        width: 1.0,
      ),
    );
  }

  /// Backward-compatible decoration method
  static BoxDecoration liquidGlassDecoration({
    double borderRadius = 14,
    Color? borderColor,
    Color? fillColor,
    bool glow = false,
  }) {
    return sonomaCardDecoration(
      borderRadius: borderRadius,
      borderColor: borderColor,
      fillColor: fillColor,
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: canvasBg,
      colorScheme: const ColorScheme.dark(
        surface: surfaceCard,
        surfaceContainerHighest: surfaceCardHover,
        primary: accentBlue,
        secondary: mintGreen,
        error: roseDanger,
        onSurface: textPrimary,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: borderSubtle, width: 1.0),
        ),
        color: surfaceCard,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: canvasBg,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: borderSubtle, width: 1.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: borderSubtle,
        thickness: 1.0,
        space: 1.0,
      ),
    );
  }

  static ThemeData lightTheme() => darkTheme(); // Enforce Clean Sonoma Dark Theme
}

/// A clean Sonoma Card widget with solid surface, crisp 1px border, and zero glassmorphism
class SonomaCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? fillColor;
  final bool isSelected;

  const SonomaCard({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.borderColor,
    this.fillColor,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      decoration: CordaTheme.sonomaCardDecoration(
        borderRadius: borderRadius,
        borderColor: borderColor,
        fillColor: fillColor,
        isSelected: isSelected,
      ),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        hoverColor: CordaTheme.surfaceCardHover,
        splashColor: CordaTheme.accentBlue.withValues(alpha: 0.1),
        child: card,
      );
    }

    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }

    return card;
  }
}

/// Backward compatibility alias for LiquidGlassCard -> redirects to SonomaCard
class LiquidGlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? fillColor;
  final bool glow;

  const LiquidGlassCard({
    super.key,
    required this.child,
    this.borderRadius = 14,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.borderColor,
    this.fillColor,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    return SonomaCard(
      borderRadius: borderRadius,
      padding: padding,
      margin: margin,
      onTap: onTap,
      borderColor: borderColor,
      fillColor: fillColor,
      child: child,
    );
  }
}
