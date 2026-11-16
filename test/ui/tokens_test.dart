import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/settings.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/tokens.dart';

void main() {
  test('display style is extra-bold Manrope with tight tracking', () {
    final s = AppText.display(40);
    expect(s.fontFamily, 'Manrope');
    expect(s.fontWeight, FontWeight.w800);
    expect(s.fontVariations, contains(const FontVariation('wght', 800)));
    expect(s.letterSpacing, closeTo(-0.8, 0.001));
  });
  test('meta style is secondary ink with tabular figures', () {
    final s = AppText.meta(14);
    expect(s.color, AppColors.ink2);
    expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
  });
  test('the theme is light and uses the single accent', () {
    final t = buildAppTheme();
    expect(t.brightness, Brightness.light);
    expect(t.scaffoldBackgroundColor, AppColors.ground);
    expect(t.colorScheme.primary, AppColors.accent);
    expect(t.colorScheme.surface, AppColors.surface);
    expect(t.colorScheme.error, AppColors.live);
  });
  test('palette values match the spec', () {
    expect(AppColors.ground, const Color(0xFFE9EDF4));
    expect(AppColors.ink, const Color(0xFF0F1728));
    expect(AppColors.accent, const Color(0xFF2F5BFF));
    expect(AppColors.live, const Color(0xFFFF4D5E));
    expect(badgeTints, hasLength(6));
  });
  test('repeated items lose their shadow in remote mode', () {
    AppSettings.instance.tvMode = true;
    addTearDown(() => AppSettings.instance.tvMode = false);
    expect(AppShadows.forRepeated(), isEmpty);
    expect(AppShadows.repeatedBorder(), isNotNull);
    AppSettings.instance.tvMode = false;
    expect(AppShadows.forRepeated(), AppShadows.card);
    expect(AppShadows.repeatedBorder(), isNull);
  });
}
