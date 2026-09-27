import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_colors.dart';

/// What the user picked in Profile → Appearance.
enum AppThemeMode {
  dark,
  light,
  system;

  String get storageValue => name;

  String get label => switch (this) {
    AppThemeMode.dark => 'Dark',
    AppThemeMode.light => 'Light',
    AppThemeMode.system => 'System',
  };

  IconData get icon => switch (this) {
    AppThemeMode.dark => Icons.dark_mode_rounded,
    AppThemeMode.light => Icons.light_mode_rounded,
    AppThemeMode.system => Icons.brightness_auto_rounded,
  };

  static AppThemeMode fromStorage(String? v) =>
      AppThemeMode.values.firstWhere((m) => m.name == v, orElse: () => _default);

  /// The app shipped dark-only, so that stays the default: an existing user
  /// who never opens Appearance sees exactly what they saw before.
  static const _default = AppThemeMode.dark;
}

/// Holds the chosen theme mode, persists it, and keeps [AppColors] pointed at
/// the matching palette.
///
/// `AppColors.*` are plain statics read all over the app (not `Theme.of`), so a
/// palette swap does not by itself invalidate anything — the app is remounted
/// on change (see `main.dart`) which rebuilds every widget, `const` ones
/// included.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final instance = ThemeController._();

  static const _key = 'lu62b_theme_mode';

  AppThemeMode _mode = AppThemeMode._default;
  AppThemeMode get mode => _mode;

  /// True when the app should currently render dark — resolves [AppThemeMode.system]
  /// against the OS setting.
  bool get isDark => switch (_mode) {
    AppThemeMode.dark => true,
    AppThemeMode.light => false,
    AppThemeMode.system =>
      PlatformDispatcher.instance.platformBrightness == Brightness.dark,
  };

  AppPalette get palette => isDark ? AppPalette.dark : AppPalette.light;

  /// Read the saved choice and apply it. Called from `main()` before `runApp`.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = AppThemeMode.fromStorage(prefs.getString(_key));
    } catch (_) {
      _mode = AppThemeMode._default;
    }
    apply();
  }

  /// Point [AppColors] at the palette for the current mode.
  void apply() => AppColors.use(palette);

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    apply();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.storageValue);
    } catch (_) {}
  }

  /// Flip between light and dark. On [AppThemeMode.system] this picks the
  /// explicit opposite of what is showing right now.
  Future<void> toggle() =>
      setMode(isDark ? AppThemeMode.light : AppThemeMode.dark);

  /// Re-resolve after the OS switched dark/light while we follow the system.
  void onPlatformBrightnessChanged() {
    if (_mode != AppThemeMode.system) return;
    apply();
    notifyListeners();
  }
}
