import 'package:flutter/painting.dart';

import '../settings.dart';

/// Colours of the dark "Kömür" look: neutral charcoal with one lavender accent. Screens use these names only, never raw colour values.
abstract final class AppColors {
  static const ground = Color(0xFF0B0B0D);
  static const surface = Color(0xFF151517);
  static const surfaceAlt = Color(0xFF1E1E22);
  static const line = Color(0xFF2A2A2E);
  static const dashed = Color(0xFF3F3F46);
  static const ink = Color(0xFFF4F4F5);
  static const ink2 = Color(0xFFA1A1AA);
  static const ink3 = Color(0xFF71717A); // icons and disabled items only, never readable text
  static const body = Color(0xFFD4D4D8);
  static const accent = Color(0xFFA78BFA);
  static const onAccent = Color(0xFF120A2A);
  static const accentSoft = Color(0xFF2A2342);
  static const accentInk = Color(0xFFC4B5FD);
  static const buffered = Color(0xFF4A4A52);
  static const live = Color(0xFFFF5C6C);
  static const liveSoft = Color(0xFF3A1E24);
  static const liveInk = Color(0xFFFFB3BC);
  static const liveText = Color(0xFFFF8A96);
  static const ok = Color(0xFF7DD3A8);
  static const okSoft = Color(0xFF14301F); // ground of the "İzlendi" tag under ok text
  static const warnSoft = Color(0xFF3A2E14);
  static const warnInk = Color(0xFFF2C879);

  /// Filled rating star (the warm gold of [warnInk]); empty stars use [dashed].
  static const star = warnInk;

  /// Background of the video itself (the only dark surface).
  static const video = Color(0xFF000000);

  /// The white ground a QR code needs to stay readable.
  static const qrGround = Color(0xFFFFFFFF);

  /// Scrim over a picture under a light label (progress track on an image).
  static const onImageTrack = Color(0x73000000); // black, 45 %
  static const transparent = Color(0x00000000);

  /// The surface colour at zero opacity: the far end of the scene-to-card fade.
  static const surfaceClear = Color(0x00151517);

  /// Frosted dark charcoal surface for floating iPhone navigation and player overlays.
  static const glass = Color(0xD9151517);

  /// Darker translucent surface for controls floating directly over video.
  static const videoGlass = Color(0xBF121216);

  /// Subtle hairline rim around frosted glass surfaces on OLED dark ground.
  static const glassBorder = Color(0xFF2E2E36);

  /// Ground colour at zero opacity for hero backdrop fades into the page ground.
  static const groundClear = Color(0x000B0B0D);

  /// Top/bottom dark gradient scrim over full-bleed video.
  static const videoScrim = Color(0xA6000000);
}

/// Soft (background, text) pairs for channel badges and profile circles.
const List<(Color bg, Color ink)> badgeTints = [
  (Color(0xFF3A1E24), Color(0xFFFFB3BC)),
  (Color(0xFF2A2342), Color(0xFFC4B5FD)),
  (Color(0xFF3A2E14), Color(0xFFF2C879)),
  (Color(0xFF14301F), Color(0xFF7DD3A8)),
  (Color(0xFF2E2140), Color(0xFFD8B4FE)),
  (Color(0xFF12303A), Color(0xFF7DD3E8)),
];

abstract final class AppShadows {
  static const panel = [BoxShadow(offset: Offset(0, 14), blurRadius: 40, color: Color.fromRGBO(0, 0, 0, 0.35))];
  static const card = [BoxShadow(offset: Offset(0, 10), blurRadius: 30, color: Color.fromRGBO(0, 0, 0, 0.28))];
  static const chip = [BoxShadow(offset: Offset(0, 8), blurRadius: 24, color: Color.fromRGBO(0, 0, 0, 0.28))];
  static const lift = [BoxShadow(offset: Offset(0, 18), blurRadius: 40, color: Color.fromRGBO(0, 0, 0, 0.5))];
  static const overlay = [BoxShadow(offset: Offset(0, 20), blurRadius: 50, color: Color.fromRGBO(0, 0, 0, 0.55))];

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

/// Two voices: Fraunces (soft serif) names things; Hanken Grotesk (sans) does the interface work.
abstract final class AppText {
  /// The interface family (also the theme default).
  static const family = 'HankenGrotesk';
  static const serif = 'Fraunces';

  static TextStyle _sans(double size, int weight, Color color, {double? spacing, double? height, bool tabular = false, bool italic = false}) => TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        fontVariations: [FontVariation('wght', weight.toDouble())],
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        letterSpacing: spacing,
        height: height,
        color: color,
      );

  static TextStyle _serif(double size, int weight, Color color, {double? spacing, double? height}) => TextStyle(
        fontFamily: serif,
        fontSize: size,
        fontWeight: FontWeight.values[(weight ~/ 100) - 1],
        // opsz follows the size so big titles get the fine display cut and small names the sturdy text cut; SOFT rounds the corners.
        fontVariations: [FontVariation('wght', weight.toDouble()), FontVariation('opsz', size.clamp(9.0, 144.0)), const FontVariation('SOFT', 60), const FontVariation('WONK', 0)],
        letterSpacing: spacing,
        height: height,
        color: color,
      );

  /// Page titles and big card titles.
  static TextStyle display(double size, {Color color = AppColors.ink}) => _serif(size, 650, color, spacing: size * -0.015, height: 1.12);

  /// Section headings, card and row names.
  static TextStyle title(double size, {Color color = AppColors.ink}) => _serif(size, 600, color, height: 1.2);

  /// Buttons and tags.
  static TextStyle label(double size, {Color color = AppColors.ink}) => _sans(size, 700, color);

  /// Secondary lines, counts, time ranges (tabular figures).
  static TextStyle meta(double size, {Color color = AppColors.ink2}) => _sans(size, 600, color, tabular: true);

  /// What is on air: programme names, quieter and slanted so they never read as a channel name.
  static TextStyle note(double size, {Color color = AppColors.ink2}) => _sans(size, 400, color, italic: true);

  /// Description paragraphs.
  static TextStyle body({double size = 15, Color color = AppColors.body}) => _sans(size, 500, color, height: 1.55);
}
