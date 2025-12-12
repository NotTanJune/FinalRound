import 'package:flutter/material.dart';

/// App theme configuration matching iOS AppTheme.swift exactly
class AppTheme {
  // MARK: - Primary Brand Colors
  static const Color primary = Color(0xFF0F8A4A);
  
  // MARK: - Background Colors (Light Mode defaults, with Dark Mode support)
  static Color background(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF1C1C1E) 
          : const Color(0xFFF2F2F7);
  
  static Color cardBackground(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF2C2C2E) 
          : Colors.white;
  
  static Color elevatedSurface(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF3A3A3C) 
          : Colors.white;
  
  static Color inputBackground(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF2C2C2E) 
          : const Color(0xFFF2F2F7);
  
  // MARK: - Text Colors
  static Color textPrimary(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? Colors.white 
          : const Color(0xFF1C1C1E);
  
  static Color textSecondary(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF8E8E93) 
          : const Color(0xFF6C6C70);
  
  static Color textTertiary(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF636366) 
          : const Color(0xFFAEAEB2);
  
  // MARK: - UI Colors
  static Color border(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? const Color(0xFF38383A) 
          : const Color(0xFFE5E5EA);
  
  static const Color lightGreen = Color(0xFFE8F5E9);
  static Color shadowColor(BuildContext context) => 
      Theme.of(context).brightness == Brightness.dark 
          ? Colors.black.withOpacity(0.3) 
          : Colors.black.withOpacity(0.08);
  
  // MARK: - Accent Colors
  static const Color ratingYellow = Color(0xFFF7D44C);
  static const Color accentBlue = Color(0xFF4285F4);
  static const Color accentViolet = Color(0xFFA788FF);
  static const Color softRed = Color(0xFFE4574D);
  
  // MARK: - Status Colors
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9500);
  static const Color error = Color(0xFFFF3B30);
  
  // MARK: - Typography
  static TextStyle font({
    required double size,
    FontWeight weight = FontWeight.normal,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: 'Nohemi',
      fontSize: size,
      fontWeight: weight,
      color: color,
    );
  }
  
  // Semantic font styles
  static TextStyle largeTitle(BuildContext context) => font(
    size: 34,
    weight: FontWeight.bold,
    color: textPrimary(context),
  );
  
  static TextStyle title(BuildContext context) => font(
    size: 28,
    weight: FontWeight.bold,
    color: textPrimary(context),
  );
  
  static TextStyle title2(BuildContext context) => font(
    size: 24,
    weight: FontWeight.w600,
    color: textPrimary(context),
  );
  
  static TextStyle title3(BuildContext context) => font(
    size: 20,
    weight: FontWeight.w600,
    color: textPrimary(context),
  );
  
  static TextStyle headline(BuildContext context) => font(
    size: 18,
    weight: FontWeight.w600,
    color: textPrimary(context),
  );
  
  static TextStyle body(BuildContext context) => font(
    size: 16,
    weight: FontWeight.normal,
    color: textPrimary(context),
  );
  
  static TextStyle callout(BuildContext context) => font(
    size: 15,
    weight: FontWeight.normal,
    color: textPrimary(context),
  );
  
  static TextStyle subheadline(BuildContext context) => font(
    size: 14,
    weight: FontWeight.normal,
    color: textSecondary(context),
  );
  
  static TextStyle footnote(BuildContext context) => font(
    size: 13,
    weight: FontWeight.normal,
    color: textSecondary(context),
  );
  
  static TextStyle caption(BuildContext context) => font(
    size: 12,
    weight: FontWeight.normal,
    color: textTertiary(context),
  );
  
  // MARK: - Theme Data
  static ThemeData lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primary,
      scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: lightGreen,
        surface: Colors.white,
        error: error,
      ),
      fontFamily: 'Nohemi',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
  
  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primary,
      scaffoldBackgroundColor: const Color(0xFF1C1C1E),
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: lightGreen,
        surface: const Color(0xFF2C2C2E),
        error: error,
      ),
      fontFamily: 'Nohemi',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}

// MARK: - Decorations
class AppCardDecoration extends BoxDecoration {
  AppCardDecoration(BuildContext context)
      : super(
          color: AppTheme.cardBackground(context),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.shadowColor(context),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        );
}

// MARK: - Button Styles
class PrimaryButtonStyle extends ButtonStyle {
  PrimaryButtonStyle()
      : super(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return AppTheme.primary.withOpacity(0.9);
            }
            return AppTheme.primary;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          textStyle: WidgetStateProperty.all(
            AppTheme.font(size: 16, weight: FontWeight.w600),
          ),
        );
}

class SecondaryButtonStyle extends ButtonStyle {
  SecondaryButtonStyle()
      : super(
          backgroundColor: WidgetStateProperty.all(AppTheme.lightGreen),
          foregroundColor: WidgetStateProperty.all(AppTheme.primary),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          textStyle: WidgetStateProperty.all(
            AppTheme.font(size: 16, weight: FontWeight.w600),
          ),
        );
}

// MARK: - Extensions
extension HexColor on Color {
  static Color fromHex(String hexString) {
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
