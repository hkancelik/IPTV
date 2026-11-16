import 'package:flutter/material.dart';

import 'ui/tokens.dart';

/// Network poster decoded at thumbnail size (full-size posters cost ~1.5 MB each once decoded).
class PosterImage extends StatelessWidget {
  const PosterImage(this.url, {super.key, this.size = double.infinity, this.fit = BoxFit.cover, this.cacheWidth = 260, this.placeholder});

  final String url;
  final double size;
  final BoxFit fit;
  final int cacheWidth;

  /// Shown when there is no picture or it fails to load.
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final h = size == double.infinity ? null : size;
    final fallback = placeholder ??
        Container(width: size, height: h, color: AppColors.surfaceAlt, child: const Icon(Icons.image_not_supported_outlined, size: 20, color: AppColors.ink3));
    if (url.isEmpty) return fallback;
    return Image.network(url, width: size, height: h, fit: fit, cacheWidth: cacheWidth, errorBuilder: (_, _, _) => fallback);
  }
}
