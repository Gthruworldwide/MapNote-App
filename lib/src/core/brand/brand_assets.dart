/// Bundled MapNote brand lockup, as two transparent vector parts.
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
/// the themed About card. The mark is regenerated from the Figma frame with
/// `tool/gen_brand_logo.ps1`; the "MapNote" wordmark is regenerated from the
/// bundled Manrope font with `tool/gen_wordmark.js` - see the README's "Brand
/// logo" section.
class BrandAssets {
  const BrandAssets._();

  /// The location-pin / notebook mark, on its own.
  static const String mark = 'assets/brand/route_note_mark.svg';

  /// The "MapNote" wordmark: blue "Map", cyan "Note".
  static const String wordmark = 'assets/brand/route_note_wordmark.svg';
}
