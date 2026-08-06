import 'package:flutter/material.dart';

import '../app_theme/app_colors.dart';

/// Base tone of a placeholder block.
const Color kSkeletonBase = AppColors.grey200;

/// Brighter tone that sweeps across [kSkeletonBase] while content loads.
const Color kSkeletonHighlight = Color(0xFFF7F7F7);

/// Drives the shimmer for every [SkeletonBox] beneath it.
///
/// One controller per skeleton screen: the boxes read the sweep from this
/// scope, so a page full of placeholders animates in phase instead of each
/// block spinning up its own ticker. Nesting is safe — an inner
/// [SkeletonShimmer] defers to the outermost one. Without any ancestor the
/// boxes still render, just flat.
class SkeletonShimmer extends StatefulWidget {
  const SkeletonShimmer({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final Duration period;

  @override
  State<SkeletonShimmer> createState() => _SkeletonShimmerState();
}

class _SkeletonShimmerState extends State<SkeletonShimmer>
    with SingleTickerProviderStateMixin {
  // Created lazily so a nested shimmer that defers to an ancestor never starts
  // a ticker of its own.
  AnimationController? _controller;

  AnimationController get _sweep =>
      _controller ??= AnimationController(vsync: this, duration: widget.period)
        ..repeat();

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (SkeletonScope.maybeOf(context) != null) return widget.child;
    return SkeletonScope(animation: _sweep, child: widget.child);
  }
}

/// Carries the shared sweep animation down to the placeholder blocks.
class SkeletonScope extends InheritedWidget {
  const SkeletonScope({
    super.key,
    required this.animation,
    required super.child,
  });

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SkeletonScope>()?.animation;

  @override
  bool updateShouldNotify(SkeletonScope oldWidget) =>
      oldWidget.animation != animation;
}

/// A single grey placeholder block.
///
/// With no [width]/[height] it fills whatever its parent gives it, so it can be
/// dropped straight into an `AspectRatio` or an `Expanded`.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 8,
    this.shape = BoxShape.rectangle,
    this.margin = EdgeInsets.zero,
  });

  final double? width;
  final double? height;
  final double radius;
  final BoxShape shape;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final borderRadius =
        shape == BoxShape.circle ? null : BorderRadius.circular(radius);
    final animation = SkeletonScope.maybeOf(context);

    if (animation == null) {
      return Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: kSkeletonBase,
          shape: shape,
          borderRadius: borderRadius,
        ),
      );
    }

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // Highlight band travels from just off the left edge to just off the
        // right; outside that span the gradient clamps to the base tone.
        final centre = animation.value * 4 - 2;
        return Container(
          width: width,
          height: height,
          margin: margin,
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: borderRadius,
            gradient: LinearGradient(
              begin: Alignment(centre - 1, 0),
              end: Alignment(centre + 1, 0),
              colors: const [
                kSkeletonBase,
                kSkeletonHighlight,
                kSkeletonBase,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Placeholder for a run of text.
///
/// Takes a fraction of the available width unless an explicit [width] is given.
/// Inside a `Row`, always pass [width] or wrap it in an `Expanded` — the
/// fractional form needs a bounded width to measure against.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.widthFactor = 1,
    this.width,
    this.height = 12,
    this.radius = 6,
    this.alignment = Alignment.centerLeft,
    this.margin = EdgeInsets.zero,
  });

  final double widthFactor;
  final double? width;
  final double height;
  final double radius;
  final Alignment alignment;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final box = SkeletonBox(
      width: width,
      height: height,
      radius: radius,
      margin: margin,
    );

    if (width != null) return Align(alignment: alignment, child: box);

    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        alignment: alignment,
        widthFactor: widthFactor.clamp(0.0, 1.0),
        child: box,
      ),
    );
  }
}

/// Round placeholder — avatars, store logos, icon buttons.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, required this.size, this.margin = EdgeInsets.zero});

  final double size;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => SkeletonBox(
        width: size,
        height: size,
        shape: BoxShape.circle,
        margin: margin,
      );
}
