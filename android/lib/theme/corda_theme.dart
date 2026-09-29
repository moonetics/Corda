import 'dart:ui';
import 'package:flutter/material.dart';

class CordaTheme {
  // Brand Colors (Apple Sonoma Luminous Aqua & Obsidian Glass standard)
  static const Color aquaPrimary = Color(0xFF0A84FF);
  static const Color aquaCyan = Color(0xFF00D2D3);
  static const Color mintGreen = Color(0xFF34C759);
  static const Color amberWarning = Color(0xFFFF9500);
  static const Color roseDanger = Color(0xFFFF453A);

  // Background surfaces
  static const Color obsidianBg = Color(0xFF070B14);
  static const Color obsidianGlass = Color(0xCC0D1527);
  static const Color obsidianGlassBorder = Color(0x24FFFFFF);

  static const LinearGradient aquaGradient = LinearGradient(
    colors: [aquaPrimary, aquaCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardHeaderGradient = LinearGradient(
    colors: [Color(0xFF0A84FF), Color(0xFF0072D6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient specularHighlightGradient = LinearGradient(
    colors: [
      Color(0x2EFFFFFF),
      Color(0x05FFFFFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration liquidGlassDecoration({
    double borderRadius = 20,
    Color? borderColor,
    Color? fillColor,
    bool glow = false,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      color: fillColor ?? obsidianGlass,
      border: Border.all(
        color: borderColor ?? obsidianGlassBorder,
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        if (glow)
          BoxShadow(
            color: aquaCyan.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 2,
          ),
      ],
    );
  }

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: aquaPrimary,
        brightness: Brightness.dark,
        surface: obsidianGlass,
        surfaceContainerHighest: const Color(0xFF131D31),
      ),
      scaffoldBackgroundColor: obsidianBg,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: obsidianGlassBorder),
        ),
        color: obsidianGlass,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: aquaPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: aquaCyan,
          side: const BorderSide(color: obsidianGlassBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }

  static ThemeData lightTheme() => darkTheme(); // Enforce Sonoma Liquid Glass Dark Aesthetic
}

/// A reusable macOS Sonoma Liquid Glassmorphism card widget with backdrop blur,
/// specular highlights, and continuous curves.
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
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.onTap,
    this.borderColor,
    this.fillColor,
    this.glow = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget cardContent = Container(
      decoration: CordaTheme.liquidGlassDecoration(
        borderRadius: borderRadius,
        borderColor: borderColor,
        fillColor: fillColor,
        glow: glow,
      ),
      padding: padding,
      child: child,
    );

    if (onTap != null) {
      cardContent = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: cardContent,
      );
    }

    Widget glass = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: cardContent,
      ),
    );

    if (margin != null) {
      glass = Padding(padding: margin!, child: glass);
    }

    return glass;
  }
}
