import 'package:flutter/material.dart';

import 'library.dart';
import 'ui/tokens.dart';

/// Network poster decoded at thumbnail size (full-size posters cost ~1.5 MB each once decoded).
///
/// When [rating] is given, a compact "★ 4.5" badge is drawn in the top-left corner of the poster.
class PosterImage extends StatelessWidget {
  const PosterImage(
    this.url, {
    super.key,
    this.size = double.infinity,
    this.fit = BoxFit.cover,
    this.cacheWidth = 260,
    this.placeholder,
    this.rating,
  });

  final String url;
  final double size;
  final BoxFit fit;
  final int cacheWidth;

  /// Shown when there is no picture or it fails to load.
  final Widget? placeholder;

  /// Optional personal rating (0.5–5.0) rendered as a corner badge on the poster.
  final double? rating;

  @override
  Widget build(BuildContext context) {
    final h = size == double.infinity ? null : size;
    final fallback = placeholder ??
        Container(width: size, height: h, color: AppColors.surfaceAlt, child: const Icon(Icons.image_not_supported_outlined, size: 20, color: AppColors.ink3));
    final pic = url.isEmpty ? fallback : Image.network(url, width: size, height: h, fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
    final r = MediaLogEntry.normalizeRating(rating);
    if (r == null) return pic;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        pic,
        Positioned(
          left: 6,
          top: 6,
          child: IgnorePointer(child: PosterRatingBadge(rating: r)),
        ),
      ],
    );
  }
}

/// Corner "★ 4.5" pill placed on a rated movie or series poster.
class PosterRatingBadge extends StatelessWidget {
  const PosterRatingBadge({super.key, required this.rating, this.compact = false});

  final double rating;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final r = MediaLogEntry.normalizeRating(rating) ?? rating;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 7.5, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: AppColors.warnSoft,
        borderRadius: BorderRadius.circular(AppSizes.tagRadius),
        border: Border.all(color: AppColors.glassBorder, width: 0.8),
        boxShadow: AppShadows.chip,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: compact ? 11.5 : 13, color: AppColors.star),
          const SizedBox(width: 3),
          Text(
            MediaLogEntry.formatRating(r),
            style: AppText.meta(compact ? 11 : 12, color: AppColors.warnInk),
          ),
        ],
      ),
    );
  }
}
