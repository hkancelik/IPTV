import 'package:flutter/material.dart';

import 'tokens.dart';

/// The light "Gündüz" theme. Focus is drawn by FocusRing, so Material's own focus and hover tints are off.
ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.ink,
    onSecondary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    error: AppColors.live,
    onError: AppColors.onAccent,
  );
  final base = ThemeData(brightness: Brightness.light, useMaterial3: true, colorScheme: scheme, fontFamily: AppText.family);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.ground,
    splashFactory: NoSplash.splashFactory,
    focusColor: AppColors.transparent,
    hoverColor: AppColors.transparent,
    highlightColor: AppColors.transparent,
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink, fontFamily: AppText.family),
    iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
    inputDecorationTheme: InputDecorationTheme(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      filled: false,
      isDense: true,
      hintStyle: AppText.meta(15),
      labelStyle: AppText.meta(15),
      prefixIconColor: AppColors.ink2,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent, linearTrackColor: AppColors.line, circularTrackColor: AppColors.transparent),
    textSelectionTheme: TextSelectionThemeData(cursorColor: AppColors.accent, selectionColor: AppColors.accent.withValues(alpha: 0.25), selectionHandleColor: AppColors.accent),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: const WidgetStatePropertyAll(AppColors.dashed),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
