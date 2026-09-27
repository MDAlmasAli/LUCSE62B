import 'package:flutter/material.dart';

/// One complete set of color tokens. Two instances exist — [AppPalette.dark]
/// and [AppPalette.light] — and [AppColors] reads whichever is active, so the
/// whole app re-colors by swapping a single object.
///
/// Values mirror the website's CSS variables in `assets/css/style.css`
/// (`:root` for dark, `html[data-theme="light"]` for light) so the app and the
/// site look like the same product.
@immutable
class AppPalette {
  final bool isDark;

  // Brand / accent
  final Color accent;
  final Color accent2;
  final Color accentBright;
  final Color accentCyan;

  // Backgrounds
  final Color bg;
  final Color surface;
  final Color card;
  final Color cardElevated;

  // Text
  final Color text;
  final Color textBright;
  final Color textSecondary;
  final Color muted;

  // Status
  final Color green;
  final Color red;
  final Color amber;

  /// Vivid hues used for category chips, badges and status text. The dark set
  /// is the Tailwind 400 range, which washes out on white — the light set drops
  /// to the 600/700 range so the same label stays readable on a white card.
  final Color greenBright;
  final Color amberBright;
  final Color redBright;
  final Color blueBright;
  final Color orangeBright;
  final Color pinkBright;
  final Color indigoBright;
  final Color cyanBright;
  final Color tealBright;

  // Borders
  final Color border;
  final Color borderAccent;

  /// Fill for a subtly tinted surface (input fields, chips) — white-on-dark,
  /// black-on-light, so `withValues(alpha:)` tricks that assumed a dark
  /// background stay legible.
  final Color tint;

  const AppPalette({
    required this.isDark,
    required this.accent,
    required this.accent2,
    required this.accentBright,
    required this.accentCyan,
    required this.bg,
    required this.surface,
    required this.card,
    required this.cardElevated,
    required this.text,
    required this.textBright,
    required this.textSecondary,
    required this.muted,
    required this.green,
    required this.red,
    required this.amber,
    required this.greenBright,
    required this.amberBright,
    required this.redBright,
    required this.blueBright,
    required this.orangeBright,
    required this.pinkBright,
    required this.indigoBright,
    required this.cyanBright,
    required this.tealBright,
    required this.border,
    required this.borderAccent,
    required this.tint,
  });

  /// The original (and default) dark theme.
  static const dark = AppPalette(
    isDark: true,
    accent: Color(0xFF7C3AED),
    accent2: Color(0xFFA855F7),
    accentBright: Color(0xFFA78BFA),
    accentCyan: Color(0xFF0891B2),
    bg: Color(0xFF0A0A14),
    surface: Color(0xFF15131F),
    card: Color(0xFF13111F),
    cardElevated: Color(0xFF1E1E2E),
    text: Color(0xFFE2D9F3),
    textBright: Color(0xFFF0E6FF),
    textSecondary: Color(0xFF94A3B8),
    muted: Color(0xFF64748B),
    green: Color(0xFF10B981),
    red: Color(0xFFF43F5E),
    amber: Color(0xFFFBBF24),
    greenBright: Color(0xFF34D399),
    amberBright: Color(0xFFFBBF24),
    redBright: Color(0xFFF87171),
    blueBright: Color(0xFF38BDF8),
    orangeBright: Color(0xFFFB923C),
    pinkBright: Color(0xFFF472B6),
    indigoBright: Color(0xFF818CF8),
    cyanBright: Color(0xFF22D3EE),
    tealBright: Color(0xFF2DD4BF),
    border: Color(0x1AFFFFFF),
    borderAccent: Color(0x337C3AED),
    tint: Color(0xFFFFFFFF),
  );

  /// Light theme. Purple-tinted rather than plain white, matching the site.
  /// Text/accent tones are darkened so they keep ~4.5:1 contrast on white.
  static const light = AppPalette(
    isDark: false,
    accent: Color(0xFF7C3AED),
    accent2: Color(0xFF9333EA),
    accentBright: Color(0xFF6D28D9),
    accentCyan: Color(0xFF0E7490),
    bg: Color(0xFFF5F3FF),
    surface: Color(0xFFEDE9FE),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFFFFFFF),
    text: Color(0xFF1E1B33),
    textBright: Color(0xFF0F172A),
    textSecondary: Color(0xFF4A3F7A),
    muted: Color(0xFF7B6FA6),
    green: Color(0xFF059669),
    red: Color(0xFFE11D48),
    amber: Color(0xFFB45309),
    greenBright: Color(0xFF059669),
    amberBright: Color(0xFFB45309),
    redBright: Color(0xFFDC2626),
    blueBright: Color(0xFF0284C7),
    orangeBright: Color(0xFFC2410C),
    pinkBright: Color(0xFFDB2777),
    indigoBright: Color(0xFF4F46E5),
    cyanBright: Color(0xFF0E7490),
    tealBright: Color(0xFF0D9488),
    border: Color(0x246D28D9),
    borderAccent: Color(0x3D7C3AED),
    tint: Color(0xFF000000),
  );
}

/// Central color tokens. Single source of truth for the whole app.
///
/// These are getters, not constants, because the active [AppPalette] can change
/// at runtime (see `ThemeController`). Widgets that read them must therefore not
/// be `const`; the app is remounted on a theme change so every widget rebuilds.
class AppColors {
  AppColors._();

  static AppPalette _palette = AppPalette.dark;

  /// The palette currently in use.
  static AppPalette get palette => _palette;

  static bool get isDark => _palette.isDark;

  /// Swap the active palette. Callers must rebuild the widget tree afterwards.
  static void use(AppPalette p) => _palette = p;

  // ── Brand / accent ──
  static Color get accent => _palette.accent;
  static Color get accent2 => _palette.accent2;
  static Color get accentBright => _palette.accentBright;
  static Color get accentCyan => _palette.accentCyan;

  // ── Backgrounds ──
  static Color get bg => _palette.bg;
  static Color get surface => _palette.surface;
  static Color get card => _palette.card;
  static Color get cardElevated => _palette.cardElevated;

  // ── Text ──
  static Color get text => _palette.text;
  static Color get textBright => _palette.textBright;
  static Color get textSecondary => _palette.textSecondary;
  static Color get muted => _palette.muted;

  // ── Status ──
  static Color get green => _palette.green;
  static Color get red => _palette.red;
  static Color get amber => _palette.amber;
  static Color get greenBright => _palette.greenBright;
  static Color get amberBright => _palette.amberBright;
  static Color get redBright => _palette.redBright;
  static Color get blueBright => _palette.blueBright;
  static Color get orangeBright => _palette.orangeBright;
  static Color get pinkBright => _palette.pinkBright;
  static Color get indigoBright => _palette.indigoBright;
  static Color get cyanBright => _palette.cyanBright;
  static Color get tealBright => _palette.tealBright;

  // ── Borders ──
  static Color get border => _palette.border;
  static Color get borderAccent => _palette.borderAccent;

  /// Base color for translucent fills — white on dark, black on light.
  /// `AppColors.tint.withValues(alpha: .05)` reads correctly in both themes.
  static Color get tint => _palette.tint;

  // ── Gradients ──
  static LinearGradient get accentGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  static const loginPanelGradient = LinearGradient(
    begin: Alignment(-0.6, -1),
    end: Alignment(0.6, 1),
    colors: [Color(0xFF5B21B6), Color(0xFF7C3AED), Color(0xFF0891B2)],
    stops: [0.0, 0.4, 1.0],
  );

  /// Deterministic avatar gradient from a name (mirrors analytics.js `_avatarGrad`).
  static const List<List<Color>> avatarGradients = [
    [Color(0xFF7C3AED), Color(0xFFA855F7)],
    [Color(0xFF2563EB), Color(0xFF38BDF8)],
    [Color(0xFF059669), Color(0xFF34D399)],
    [Color(0xFFDC2626), Color(0xFFF87171)],
    [Color(0xFFD97706), Color(0xFFFBBF24)],
    [Color(0xFFDB2777), Color(0xFFF472B6)],
    [Color(0xFF7C3AED), Color(0xFFEC4899)],
    [Color(0xFF0891B2), Color(0xFF22D3EE)],
  ];

  static LinearGradient avatarGradient(String name) {
    var h = 0;
    for (var i = 0; i < name.length; i++) {
      h = (h * 31 + name.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    final pair = avatarGradients[h % avatarGradients.length];
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: pair,
    );
  }
}
