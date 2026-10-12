import 'package:flutter/material.dart';

/// A RouteNote brand lockup, sized by [width] and scaled with high-quality
/// filtering.
///
/// The bundled PNGs are transparent, so the same widget reads correctly on the
/// light and dark brand surfaces. A missing asset (for example in a widget test
/// bundle) renders nothing rather than throwing.
class BrandLogo extends StatelessWidget {
  const BrandLogo(this.asset, {super.key, this.width = 200});

  /// Asset path, normally one of the `BrandAssets` constants.
  final String asset;

  /// Rendered width in logical pixels; the height follows the asset ratio.
  final double width;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: width,
      filterQuality: FilterQuality.high,
      errorBuilder: (
        BuildContext context,
        Object error,
        StackTrace? stackTrace,
      ) => const SizedBox.shrink(),
    );
  }
}
