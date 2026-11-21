import 'package:flutter/material.dart';

import '../poster_card.dart';
import 'focus_ring.dart';
import 'format.dart';
import 'tokens.dart';

enum AppButtonVariant { primary, secondary, onPage, danger }

/// Pill-shaped button. Icon-only buttons are round.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    this.label,
    this.icon,
    this.trailingIcon,
    this.prefix,
    required this.onPressed,
    this.variant = AppButtonVariant.secondary,
    this.height = AppSizes.buttonHeight,
    this.width,
    this.autofocus = false,
    this.focusNode,
    this.tooltip,
    this.child,
    this.dense = false,
  });

  final String? label;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Faint prefix before the label ("Sırala:").
  final String? prefix;
  final VoidCallback? onPressed; // null: faded and not clickable
  final AppButtonVariant variant;
  final double height;
  final double? width;
  final bool autofocus;
  final FocusNode? focusNode;
  final String? tooltip;

  /// Used instead of [label] (e.g. a label with a switch inside).
  final Widget? child;

  /// Tighter padding and a 14 px label, for narrow panels.
  final bool dense;

  (Color, Color) get _colors => switch (variant) {
    AppButtonVariant.primary => (AppColors.accent, AppColors.onAccent),
    AppButtonVariant.secondary => (AppColors.surfaceAlt, AppColors.ink),
    AppButtonVariant.onPage => (AppColors.surface, AppColors.ink),
    AppButtonVariant.danger => (AppColors.liveSoft, AppColors.liveInk),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    final enabled = onPressed != null;
    final iconOnly = label == null && child == null && prefix == null && icon != null;
    final small = dense || height < AppSizes.buttonHeight;
    final iconSize = small ? 18.0 : 20.0;
    final text = AppText.label(small ? 14 : 15, color: fg);
    final pad = dense ? 12.0 : (height >= AppSizes.primaryHeight ? 22.0 : (small ? 14.0 : 18.0));
    final box = Container(
      height: height,
      width: iconOnly ? (width ?? height) : width,
      padding: iconOnly ? EdgeInsets.zero : EdgeInsets.symmetric(horizontal: pad),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: variant == AppButtonVariant.onPage ? AppShadows.chip : null,
      ),
      // Shrink-wraps its content unless the parent forces a width (Container + alignment would fill any space).
      child: Center(
        widthFactor: 1,
        child: iconOnly
            ? Icon(icon, size: iconSize, color: fg)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[Icon(icon, size: iconSize, color: fg), SizedBox(width: dense ? 6 : 8)],
                  if (prefix != null) ...[Text(prefix!, style: AppText.meta(small ? 14 : 15)), const SizedBox(width: 6)],
                  if (label != null)
                    Flexible(
                      child: Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis, style: text),
                    ),
                  if (child != null)
                    Flexible(
                      child: DefaultTextStyle(style: text, child: child!),
                    ),
                  if (trailingIcon != null) ...[const SizedBox(width: 6), Icon(trailingIcon, size: iconSize, color: fg)],
                ],
              ),
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: FocusRing(
        radius: height / 2,
        onTap: onPressed,
        enabled: enabled,
        autofocus: autofocus,
        focusNode: focusNode,
        tooltip: tooltip,
        semanticLabel: iconOnly ? tooltip : null,
        child: box,
      ),
    );
  }
}

/// White rounded card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.radius = AppSizes.panelRadius,
    this.padding = EdgeInsets.zero,
    this.shadows = AppShadows.panel,
    this.border,
    this.color = AppColors.surface,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow> shadows;
  final BoxBorder? border;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius), boxShadow: shadows, border: border),
    child: child,
  );
}

enum PillTone { accent, live, warn, ok, neutral, onImage }

/// Small tag.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.tone = PillTone.neutral, this.icon, this.leading, this.height = 28});

  final String text;
  final PillTone tone;
  final IconData? icon;
  final Widget? leading;
  final double height;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      PillTone.accent => (AppColors.accentSoft, AppColors.accentInk),
      PillTone.live => (AppColors.liveSoft, AppColors.liveInk),
      PillTone.warn => (AppColors.warnSoft, AppColors.warnInk),
      PillTone.ok => (AppColors.okSoft, AppColors.ok),
      PillTone.neutral => (AppColors.surfaceAlt, AppColors.body),
      PillTone.onImage => (AppColors.surface, AppColors.ink),
    };
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppSizes.tagRadius)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 5)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.label(height >= 28 ? 13 : 12, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Red "live" dot.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key, this.size = 9});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
  );
}

/// Square channel badge: the logo on white, or a two-letter abbreviation on a soft tint.
class ChannelBadge extends StatelessWidget {
  const ChannelBadge({super.key, required this.name, this.logo = '', this.size = 46});

  final String name;
  final String logo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = tintFor(name);
    final radius = BorderRadius.circular(size / 3);
    final letters = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: radius),
      child: Text(badgeText(name), maxLines: 1, style: AppText.title(size * 0.28 < 12 ? 12 : size * 0.28, color: fg)),
    );
    if (logo.isEmpty) return letters;
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: radius,
        border: Border.all(color: AppColors.line),
      ),
      child: PosterImage(
        logo,
        fit: BoxFit.contain,
        cacheWidth: 160,
        placeholder: Center(
          child: Text(badgeText(name), maxLines: 1, style: AppText.title(size * 0.28 < 12 ? 12 : size * 0.28, color: fg)),
        ),
      ),
    );
  }
}

/// Rounded progress bar. Values outside 0..1 are clipped, NaN counts as 0.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.height = 6, this.onImage = false});

  final double value;
  final double height;
  final bool onImage;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final r = BorderRadius.circular(height / 2);
    return Container(
      height: height,
      decoration: BoxDecoration(color: onImage ? AppColors.onImageTrack : AppColors.line, borderRadius: r),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: v,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: onImage ? AppColors.surface : AppColors.accent, borderRadius: r),
        ),
      ),
    );
  }
}
