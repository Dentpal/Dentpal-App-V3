import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../app_theme/app_colors.dart';

/// A single choke-point for remote images across the app.
///
/// Wraps [CachedNetworkImage] and always bounds the *decoded* resolution to the
/// widget's on-screen slot (× device pixel ratio, capped). Without this, a full
/// 1024×1024 source is decoded into memory even for a 60px thumbnail — the main
/// source of memory pressure / jank on the web build, especially on mobile.
///
/// Only a single decode dimension is passed to [CachedNetworkImage] so the codec
/// preserves the source aspect ratio (setting both would distort non-square
/// images under [BoxFit.cover]).
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.cacheKey,
    this.maxDecodeDimension = 1080,
    this.placeholder,
    this.errorWidget,
    this.backgroundColor = AppColors.grey100,
    this.errorIconSize = 24,
  });

  /// Remote image URL. When null/empty the error placeholder is shown.
  final String? url;

  /// Logical slot size, used **only** to compute the decode resolution. The
  /// widget itself fills whatever bounded box its parent gives it (via [fit]),
  /// so every call site should wrap it in a `SizedBox`/`AspectRatio`/`ClipRRect`
  /// with finite constraints.
  final double? width;
  final double? height;

  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Optional stable cache key (e.g. the URL without a `?v=` cache-buster).
  final String? cacheKey;

  /// Absolute upper bound on the decoded dimension in pixels. Bump this for
  /// large hero/banner/detail images that are meant to render at full quality.
  final int maxDecodeDimension;

  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final Color backgroundColor;
  final double errorIconSize;

  double _finite(double? v) => (v != null && v.isFinite && v > 0) ? v : 0;

  int _decodeExtent(BuildContext context) {
    final logical = math.max(_finite(width), _finite(height));
    if (logical <= 0) return maxDecodeDimension;
    final dpr = MediaQuery.of(context).devicePixelRatio.clamp(1.0, 2.0);
    return (logical * dpr).ceil().clamp(1, maxDecodeDimension);
  }

  Widget _defaultPlaceholder(BuildContext context) => Container(
        color: backgroundColor,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ),
      );

  Widget _defaultError(BuildContext context) => Container(
        color: backgroundColor,
        child: Icon(
          Icons.image_not_supported,
          color: AppColors.grey400,
          size: errorIconSize,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (url == null || url!.isEmpty) {
      child = errorWidget?.call(context) ?? _defaultError(context);
    } else {
      final memWidth = _decodeExtent(context);
      child = CachedNetworkImage(
        imageUrl: url!,
        cacheKey: cacheKey,
        fit: fit,
        memCacheWidth: memWidth,
        maxWidthDiskCache: memWidth,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (context, _) =>
            placeholder?.call(context) ?? _defaultPlaceholder(context),
        errorWidget: (context, _, _) =>
            errorWidget?.call(context) ?? _defaultError(context),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }

  /// Bounded-decode [ImageProvider] for the rare `DecorationImage` case where a
  /// widget child isn't possible (e.g. a `BoxDecoration.image`). Pass the slot
  /// size; [dpr] defaults to 2.0 since there's no context here.
  static ImageProvider provider(
    String url, {
    double? width,
    double? height,
    double dpr = 2.0,
    int maxDecodeDimension = 1080,
  }) {
    final logical = math.max(
      (width != null && width.isFinite && width > 0) ? width : 0,
      (height != null && height.isFinite && height > 0) ? height : 0,
    );
    final extent = logical <= 0
        ? maxDecodeDimension
        : (logical * dpr).ceil().clamp(1, maxDecodeDimension);
    return ResizeImage(
      CachedNetworkImageProvider(url),
      width: extent,
    );
  }
}
