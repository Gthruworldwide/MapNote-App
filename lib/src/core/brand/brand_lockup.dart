import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'brand_assets.dart';

/// The RouteNote location-pin mark as vector, at an explicit size.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _BrandVector(BrandAssets.mark, width: width, height: height);
  }
}

/// The "RouteNote" wordmark as vector, at an explicit size.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _BrandVector(BrandAssets.wordmark, width: width, height: height);
  }
}

/// The horizontal RouteNote lockup: mark left, wordmark right, laid out with the
/// exact geometry of the Figma frame (viewBox 415x176).
///
/// [width] is the lockup's *ink* width - the assets are cropped to their ink
/// boxes - and the height follows from the design ratio. [markWrapper] and
/// [wordmarkWrapper] let a caller animate the two halves independently (the
/// splash does); both are handed the part already sized.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    required this.width,
    this.markWrapper,
    this.wordmarkWrapper,
  });

  /// The lockup's ink width in logical pixels.
  final double width;

  /// Wraps the sized mark, for example in opacity and scale.
  final Widget Function(Widget child)? markWrapper;

  /// Wraps the sized wordmark, for example in opacity and offset.
  final Widget Function(Widget child)? wordmarkWrapper;

  /// The two parts' boxes in Figma user units. `tool/gen_brand_logo.ps1` crops
  /// each SVG to exactly these boxes (`markWidth x markHeight` and
  /// `wordmarkWidth x designHeight`, sharing the same top edge), so the numbers
  /// here and there must stay in step.
  static const double markWidth = 78.5;
  static const double markHeight = 113;
  static const double gap = 26;
  static const double wordmarkWidth = 245;

  /// Ink width / height of the whole lockup, in Figma user units.
  static const double designWidth = markWidth + gap + wordmarkWidth;
  static const double designHeight = markHeight;

  /// The lockup's height for a given [width].
  static double heightFor(double width) => width * designHeight / designWidth;

  @override
  Widget build(BuildContext context) {
    final double scale = width / designWidth;

    Widget mark = BrandMark(
      width: markWidth * scale,
      height: designHeight * scale,
    );
    Widget wordmark = BrandWordmark(
      width: wordmarkWidth * scale,
      height: designHeight * scale,
    );
    if (markWrapper != null) {
      mark = markWrapper!(mark);
    }
    if (wordmarkWrapper != null) {
      wordmark = wordmarkWrapper!(wordmark);
    }

    // Both parts share the design's vertical band, so aligning their tops lines
    // the mark and the wordmark up exactly as the Figma frame does.
    return SizedBox(
      width: width,
      height: designHeight * scale,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[mark, SizedBox(width: gap * scale), wordmark],
      ),
    );
  }
}

/// A lockup part: vector, drawn at exactly [width] x [height], and silent for
/// screen readers (the lockup is decoration beside real text).
class _BrandVector extends StatelessWidget {
  const _BrandVector(this.asset, {required this.width, required this.height});

  final String asset;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: width,
      height: height,
      excludeFromSemantics: true,
      // A missing asset (for example in a widget-test bundle) renders nothing
      // rather than throwing.
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) => SizedBox(width: width, height: height),
    );
  }
}
