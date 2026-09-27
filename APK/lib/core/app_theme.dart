import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// The app's Material 3 theme, built from an [AppPalette] so the whole app
/// matches the website's purple look in both dark and light mode.
/// Fonts: Space Grotesk (display) + Inter (body), via google_fonts.
class AppTheme {
  AppTheme._();

  static ThemeData get dark => build(AppPalette.dark);
  static ThemeData get light => build(AppPalette.light);

  /// Build the theme for [p]. The palette must already be active via
  /// `AppColors.use(p)` so widgets reading `AppColors.*` agree with it.
  static ThemeData build(AppPalette p) {
    final base = p.isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    final textTheme = _textTheme(base.textTheme, p);

    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      canvasColor: p.bg,
      colorScheme:
          (p.isDark
                  ? const ColorScheme.dark(brightness: Brightness.dark)
                  : const ColorScheme.light(brightness: Brightness.light))
              .copyWith(
                primary: p.accent,
                secondary: p.accent2,
                surface: p.card,
                error: p.red,
                onPrimary: Colors.white,
                onSurface: p.text,
              ),
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: p.text),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: p.textBright,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.tint.withValues(alpha: 0.05),
        hintStyle: TextStyle(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: _inputBorder(p.border),
        enabledBorder: _inputBorder(p.border),
        focusedBorder: _inputBorder(p.accent),
        errorBorder: _inputBorder(p.red),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      dividerColor: p.border,
      splashColor: p.accent.withValues(alpha: 0.12),
      highlightColor: Colors.transparent,
    );
  }

  static OutlineInputBorder _inputBorder(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(11),
    borderSide: BorderSide(color: c),
  );

  static TextTheme _textTheme(TextTheme base, AppPalette p) {
    final inter = GoogleFonts.interTextTheme(base);
    return inter
        .copyWith(
          displayLarge: GoogleFonts.spaceGrotesk(
            textStyle: base.displayLarge,
            color: p.textBright,
            fontWeight: FontWeight.w700,
          ),
          displayMedium: GoogleFonts.spaceGrotesk(
            textStyle: base.displayMedium,
            color: p.textBright,
            fontWeight: FontWeight.w700,
          ),
          headlineMedium: GoogleFonts.spaceGrotesk(
            textStyle: base.headlineMedium,
            color: p.textBright,
            fontWeight: FontWeight.w700,
          ),
          headlineSmall: GoogleFonts.spaceGrotesk(
            textStyle: base.headlineSmall,
            color: p.textBright,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: GoogleFonts.spaceGrotesk(
            textStyle: base.titleLarge,
            color: p.text,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: GoogleFonts.spaceGrotesk(
            textStyle: base.titleMedium,
            color: p.text,
            fontWeight: FontWeight.w600,
          ),
        )
        .apply(bodyColor: p.text, displayColor: p.textBright);
  }
}
