import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings.dart';
import 'liquid_glass.dart';
import 'tokens.dart';

/// Responsive shell modes.
///
/// Desktop, Android TV and iPad keep the multi-column side-menu shell.
/// iPhone (and narrow handheld windows) adapt specifically for portrait and
/// landscape ergonomics, respecting Dynamic Island and Home Indicator safe areas.
enum AppLayoutMode {
  desktop,
  phonePortrait,
  phoneLandscape,
}

/// Resolves the layout mode for the current viewport and platform.
AppLayoutMode layoutModeOf(BuildContext context) {
  if (AppSettings.instance.tvMode) return AppLayoutMode.desktop;
  final size = MediaQuery.sizeOf(context);
  final platform = Theme.of(context).platform;
  final isPhone = (platform == TargetPlatform.iOS && size.shortestSide < 600) ||
      size.shortestSide < 420 ||
      size.width < 560;
  if (!isPhone) return AppLayoutMode.desktop;
  return size.height >= size.width ? AppLayoutMode.phonePortrait : AppLayoutMode.phoneLandscape;
}

bool isPhoneLayout(BuildContext context) => layoutModeOf(context) != AppLayoutMode.desktop;
bool isPhonePortrait(BuildContext context) => layoutModeOf(context) == AppLayoutMode.phonePortrait;
bool isPhoneLandscape(BuildContext context) => layoutModeOf(context) == AppLayoutMode.phoneLandscape;

/// Height reserved beneath scrollable content so items clear the floating iPhone bottom bar.
double phoneBottomClearance(BuildContext context) => 88 + MediaQuery.paddingOf(context).bottom;

/// Uses Cupertino swipe-back transitions on iOS / phone layouts and Material routes elsewhere.
Route<T> appRoute<T>(BuildContext context, WidgetBuilder builder) {
  if (Theme.of(context).platform == TargetPlatform.iOS || isPhoneLayout(context)) {
    return CupertinoPageRoute<T>(builder: builder);
  }
  return MaterialPageRoute<T>(builder: builder);
}

/// Subtle iOS/mobile haptic feedback; silent on desktop and TV mode.
abstract final class AppHaptics {
  static bool _enabled(BuildContext context) {
    if (AppSettings.instance.tvMode) return false;
    final p = Theme.of(context).platform;
    return p == TargetPlatform.iOS || p == TargetPlatform.android;
  }

  static void selection(BuildContext context) {
    if (_enabled(context)) HapticFeedback.selectionClick();
  }

  static void light(BuildContext context) {
    if (_enabled(context)) HapticFeedback.lightImpact();
  }

  static void medium(BuildContext context) {
    if (_enabled(context)) HapticFeedback.mediumImpact();
  }
}

/// Frosted dark charcoal capsule/card used for iPhone floating navigation and player chrome.
///
/// On iOS 26+ this renders Apple's genuine native Liquid Glass material via
/// [NativeGlassSurface]; on older iOS, Android, desktop and widget tests it
/// falls back to a dark frosted `BackdropFilter` surface.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = AppSizes.panelRadius,
    this.padding = EdgeInsets.zero,
    this.color = AppColors.glass,
    this.borderColor = AppColors.glassBorder,
    this.blur = 20,
    this.shadows = AppShadows.overlay,
    this.nativeClear = false,
    this.nativeShape,
    this.interactive = false,
    this.nativeTint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final double blur;
  final List<BoxShadow> shadows;

  /// Uses Apple's `.clear` Liquid Glass variant (recommended over rich video).
  final bool nativeClear;
  final NativeGlassShape? nativeShape;
  final bool interactive;
  final Color? nativeTint;

  @override
  Widget build(BuildContext context) {
    if (isNativeLiquidGlassSupported) {
      return NativeGlassSurface(
        clear: nativeClear,
        shape: nativeShape ?? NativeGlassShape.rect,
        cornerRadius: radius,
        padding: padding,
        tint: nativeTint,
        interactive: interactive,
        isDark: true,
        child: child,
      );
    }

    final borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: borderRadius, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius,
              border: Border.all(color: borderColor, width: 1),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Presents a rounded Kömür iOS modal bottom sheet with drag handle, title bar and safe-area padding.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  Widget? trailing,
  required WidgetBuilder builder,
  double maxHeightFraction = 0.82,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.transparent,
    barrierColor: AppColors.videoScrim,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final landscape = size.width > size.height;
      final maxHeight = size.height * (landscape ? 0.90 : maxHeightFraction);
      final maxWidth = landscape ? 560.0 : size.width;
      final keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
      return Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.panelRadius)),
                border: Border(
                  top: BorderSide(color: AppColors.glassBorder, width: 1),
                  left: BorderSide(color: AppColors.glassBorder, width: 1),
                  right: BorderSide(color: AppColors.glassBorder, width: 1),
                ),
                boxShadow: AppShadows.overlay,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 38,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: AppColors.dashed,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(21)),
                                if (subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(13)),
                                ],
                              ],
                            ),
                          ),
                          if (trailing != null) ...[const SizedBox(width: 8), trailing],
                          const SizedBox(width: 6),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(ctx).pop(),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
                              child: const Icon(Icons.close_rounded, size: 18, color: AppColors.ink2),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 1, color: AppColors.line),
                    Flexible(child: builder(ctx)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Touch-friendly selectable option row inside [showAppSheet].
class SheetOptionTile extends StatelessWidget {
  const SheetOptionTile({
    super.key,
    required this.label,
    this.subtitle,
    this.trailingText,
    this.leadingIcon,
    this.selected = false,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final String? trailingText;
  final IconData? leadingIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.selection(context);
        onTap();
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.transparent,
          borderRadius: BorderRadius.circular(AppSizes.itemRadius),
        ),
        child: Row(
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 20, color: selected ? AppColors.accentInk : AppColors.ink2),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: selected ? AppText.title(15, color: AppColors.accentInk) : AppText.label(15),
                  ),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.meta(12)),
                ],
              ),
            ),
            if (trailingText != null) ...[
              const SizedBox(width: 10),
              Text(trailingText!, style: AppText.meta(13, color: selected ? AppColors.accentInk : AppColors.ink2)),
            ],
            if (selected) ...[
              const SizedBox(width: 10),
              const Icon(Icons.check_rounded, size: 20, color: AppColors.accent),
            ],
          ],
        ),
      ),
    );
  }
}
