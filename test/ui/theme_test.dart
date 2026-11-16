import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_app/src/ui/app_theme.dart';
import 'package:iptv_app/src/ui/tokens.dart';

void main() {
  test('dialogs and menus are white rounded cards', () {
    final t = buildAppTheme();
    expect(t.dialogTheme.backgroundColor, AppColors.surface);
    expect((t.dialogTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(28));
    expect(t.popupMenuTheme.color, AppColors.surface);
    expect((t.popupMenuTheme.shape as RoundedRectangleBorder).borderRadius, BorderRadius.circular(20));
    expect(t.checkboxTheme.shape, isA<RoundedRectangleBorder>());
    expect(t.tooltipTheme.decoration, isA<BoxDecoration>());
  });
}
