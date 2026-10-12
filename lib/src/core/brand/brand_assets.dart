/// Bundled RouteNote brand lockup, as two transparent vector parts.
///
/// The lockup is split because the cold-start splash animates the mark and the
/// wordmark independently (the mark fades and scales up, the wordmark then fades
/// in and rises). Both files come from the same Figma frame, so their geometry
/// is exact: `BrandLockup` composes them with the numbers in
/// `tool/gen_brand_logo.ps1`.
///
/// They are SVGs on purpose: one pair of assets renders identically on iOS and
/// Android at any size, with no raster softness when the mark scales up.
/// The Figma artboard was dropped and the pin's chevron is punched out with an
/// SVG mask, so whatever is behind the logo shows through the chevron - the same
/// assets read correctly on the white day splash, the AMOLED night splash and
/// the themed About card. Regenerate them with `tool/gen_brand_logo.ps1` - see
/// the README's "Brand logo" section.
class BrandAssets {
  const BrandAssets._();

  /// The location-pin / notebook mark, on its own.
  static const String mark = 'assets/brand/route_note_mark.svg';

  /// The "RouteNote" wordmark: blue "Route", cyan "Note".
  static const String wordmark = 'assets/brand/route_note_wordmark.svg';
}
