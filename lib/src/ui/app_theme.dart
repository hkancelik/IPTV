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
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.transparent,
      elevation: 24,
      shadowColor: AppShadows.overlay.first.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.panelRadius)),
      titleTextStyle: AppText.display(24),
      contentTextStyle: AppText.body(),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: AppColors.transparent,
      elevation: 12,
      shadowColor: AppShadows.lift.first.color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.tileRadius)),
      textStyle: AppText.label(15),
      labelTextStyle: WidgetStatePropertyAll(AppText.label(15)),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: const WidgetStatePropertyAll(AppColors.transparent),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.tileRadius))),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.transparent),
      checkColor: const WidgetStatePropertyAll(AppColors.onAccent),
      side: const BorderSide(color: AppColors.dashed, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(AppSizes.tagRadius)),
      textStyle: AppText.label(13, color: AppColors.onAccent),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: AppText.label(14, color: AppColors.onAccent),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.itemRadius)),
    ),
  );
}
