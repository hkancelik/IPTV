import 'package:flutter/painting.dart';

import '../settings.dart';

/// Colours of the light "Gündüz" look. Screens use these names only, never raw colour values.
abstract final class AppColors {
  static const ground = Color(0xFFE9EDF4);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF2F4F9);
  static const line = Color(0xFFE3E7F0);
  static const dashed = Color(0xFFC5CCDB);
  static const ink = Color(0xFF0F1728);
  static const ink2 = Color(0xFF55607A);
  static const ink3 = Color(0xFF8A93A8); // icons and disabled items only, never readable text
  static const body = Color(0xFF3A4560);
  static const accent = Color(0xFF2F5BFF);
  static const onAccent = Color(0xFFFFFFFF);
  static const accentSoft = Color(0xFFE7ECFF);
  static const accentInk = Color(0xFF2447D6);
  static const buffered = Color(0xFFC9D2EA);
  static const live = Color(0xFFFF4D5E);
  static const liveSoft = Color(0xFFFFE3E6);
  static const liveInk = Color(0xFF8A1226);
  static const liveText = Color(0xFFC81E3A);
  static const ok = Color(0xFF0F5A2E);
  static const warnSoft = Color(0xFFFFF0D6);
  static const warnInk = Color(0xFF7A4A00);

  /// Background of the video itself (the only dark surface).
  static const video = Color(0xFF000000);

  /// The white ground a QR code needs to stay readable.
  static const qrGround = Color(0xFFFFFFFF);

  /// Scrim over a picture under a light label (progress track on an image).
  static const onImageTrack = Color(0x730F1728); // ink, 45 %
  static const transparent = Color(0x00000000);

  /// White at zero opacity: the far end of the scene-to-card fade.
  static const surfaceClear = Color(0x00FFFFFF);
}

/// Soft (background, text) pairs for channel badges and profile circles.
const List<(Color bg, Color ink)> badgeTints = [
  (Color(0xFFFFE3E6), Color(0xFF8A1226)),
  (Color(0xFFE7ECFF), Color(0xFF1E3BB8)),
  (Color(0xFFFFF0D6), Color(0xFF7A4A00)),
  (Color(0xFFDDF5E6), Color(0xFF0F5A2E)),
  (Color(0xFFEFE6FF), Color(0xFF4B1FA8)),
  (Color(0xFFDDF3F7), Color(0xFF0B5566)),
];

abstract final class AppShadows {
  static const panel = [BoxShadow(offset: Offset(0, 14), blurRadius: 40, color: Color.fromRGBO(20, 30, 70, 0.09))];
  static const card = [BoxShadow(offset: Offset(0, 10), blurRadius: 30, color: Color.fromRGBO(20, 30, 70, 0.07))];
  static const chip = [BoxShadow(offset: Offset(0, 8), blurRadius: 24, color: Color.fromRGBO(20, 30, 70, 0.07))];
  static const lift = [BoxShadow(offset: Offset(0, 18), blurRadius: 40, color: Color.fromRGBO(20, 30, 70, 0.18))];
  static const overlay = [BoxShadow(offset: Offset(0, 20), blurRadius: 50, color: Color.fromRGBO(0, 0, 0, 0.30))];

  /// Shadow of a repeated item (row, poster, card in a list). Remote mode runs on weak TV sticks: no shadow there.
  static List<BoxShadow> forRepeated() => AppSettings.instance.tvMode ? const [] : card;

  /// The thin outline that replaces [forRepeated]'s shadow in remote mode.
  static Border? repeatedBorder() => AppSettings.instance.tvMode ? Border.all(color: AppColors.line) : null;
}

abstract final class AppSizes {
  static const panelRadius = 28.0;
  static const cardRadius = 24.0;
  static const tileRadius = 20.0;
  static const itemRadius = 16.0;
  static const smallRadius = 14.0;
  static const tagRadius = 10.0;
  static const ring = 3.0;
  static const ringGap = 4.0;
  static const scrollPad = 8.0;
  static const menuWidth = 212.0;
  static const menuCompact = 76.0;
  static const sideWidth = 216.0;
  static const buttonHeight = 44.0;
  static const primaryHeight = 48.0;
}

abstract final class AppText {
  static const family = 'Manrope';

  static TextStyle _style(double size, int weight, Color color, {double? spacing, double? height, bool tabular = false}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontVariations: [FontVariation('wght', weight.toDouble())],
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        letterSpacing: spacing,
        height: height,
        color: color,
      );

  /// Page titles and big card titles.
  static TextStyle display(double size, {Color color = AppColors.ink}) => _style(size, 800, color, spacing: size * -0.02, height: 1.12);

  /// Section headings, card and row names.
  static TextStyle title(double size, {Color color = AppColors.ink}) => _style(size, 800, color);

  /// Buttons and tags.
  static TextStyle label(double size, {Color color = AppColors.ink}) => _style(size, 700, color);

  /// Secondary lines, counts, time ranges (tabular figures).
  static TextStyle meta(double size, {Color color = AppColors.ink2}) => _style(size, 600, color, tabular: true);

  /// Description paragraphs.
  static TextStyle body({double size = 15, Color color = AppColors.body}) => _style(size, 500, color, height: 1.55);
}
