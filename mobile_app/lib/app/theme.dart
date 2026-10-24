import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config.dart';

/// Semantic colours that are not part of Material's ColorScheme.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color subtext;
  final Color border;
  final Color surfaceAlt;
  final Color brandSoft; // tinted background derived from the brand colour

  const AppColors({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.subtext,
    required this.border,
    required this.surfaceAlt,
    required this.brandSoft,
  });

  @override
  AppColors copyWith({Color? success, Color? warning, Color? danger, Color? info, Color? subtext, Color? border, Color? surfaceAlt, Color? brandSoft}) => AppColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        subtext: subtext ?? this.subtext,
        border: border ?? this.border,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        brandSoft: brandSoft ?? this.brandSoft,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      subtext: Color.lerp(subtext, other.subtext, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
    );
  }
}

extension ThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// The two colours a company chooses in its settings.
@immutable
class Brand {
  final Color primary;
  final Color accent;
  const Brand(this.primary, this.accent);
  static const Brand fallback = Brand(Color(AppConfig.defaultPrimary), Color(AppConfig.defaultAccent));
}

ThemeData buildTheme(Brand brand, Brightness brightness, {required bool arabic}) {
  final dark = brightness == Brightness.dark;

  final bg = dark ? const Color(0xFF0B1020) : const Color(0xFFF5F6FA);
  final surface = dark ? const Color(0xFF151B2E) : Colors.white;
  final surfaceAlt = dark ? const Color(0xFF1C2440) : const Color(0xFFF1F3F9);
  final onSurface = dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  final subtext = dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  final border = dark ? const Color(0xFF263049) : const Color(0xFFE6E8F0);

  final scheme = ColorScheme.fromSeed(seedColor: brand.primary, brightness: brightness).copyWith(
    primary: brand.primary,
    onPrimary: Colors.white,
    secondary: brand.accent,
    onSecondary: Colors.white,
    surface: surface,
    onSurface: onSurface,
    surfaceContainerHighest: surfaceAlt,
    outline: border,
    error: const Color(0xFFEF4444),
  );

  final base = ThemeData(brightness: brightness, useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: bg);
  final textTheme = (arabic ? GoogleFonts.cairoTextTheme(base.textTheme) : GoogleFonts.interTextTheme(base.textTheme))
      .apply(bodyColor: onSurface, displayColor: onSurface);

  final radius14 = BorderRadius.circular(14);
  OutlineInputBorder inputBorder(Color c, [double w = 1]) => OutlineInputBorder(borderRadius: radius14, borderSide: BorderSide(color: c, width: w));

  return base.copyWith(
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    extensions: [
      AppColors(
        success: const Color(0xFF10B981),
        warning: const Color(0xFFF59E0B),
        danger: const Color(0xFFEF4444),
        info: const Color(0xFF3B82F6),
        subtext: subtext,
        border: border,
        surfaceAlt: surfaceAlt,
        brandSoft: brand.primary.withValues(alpha: dark ? 0.18 : 0.10),
      ),
    ],
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 20),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: border)),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? surfaceAlt : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder(border),
      enabledBorder: inputBorder(border),
      focusedBorder: inputBorder(brand.primary, 1.6),
      errorBorder: inputBorder(scheme.error),
      focusedErrorBorder: inputBorder(scheme.error, 1.6),
      labelStyle: TextStyle(color: subtext),
      hintStyle: TextStyle(color: subtext.withValues(alpha: 0.8)),
      prefixIconColor: subtext,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: radius14),
        side: BorderSide(color: border),
        foregroundColor: onSurface,
        textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius14),
        textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: brand.primary.withValues(alpha: dark ? 0.28 : 0.14),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => textTheme.labelSmall?.copyWith(
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? brand.primary : subtext,
          )),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(size: 24, color: s.contains(WidgetState.selected) ? brand.primary : subtext)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      backgroundColor: dark ? const Color(0xFF2A3454) : const Color(0xFF1E293B),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceAlt,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: textTheme.labelLarge,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : subtext),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? brand.primary : border),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    listTileTheme: ListTileThemeData(contentPadding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: brand.primary,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: brand.primary),
  );
}

// ------------------------------------------------------------ dark mode preference

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString('theme_mode')) {
      case 'dark':
        state = ThemeMode.dark;
      case 'light':
        state = ThemeMode.light;
      default:
        state = ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) => ThemeModeNotifier());
