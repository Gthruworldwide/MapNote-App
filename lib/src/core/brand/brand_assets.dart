/// Bundled RouteNote brand lockups.
///
/// The PNGs are transparent: the Figma artboard was dropped and the pin's
/// chevron is punched out, so one asset reads correctly on white *and* black
/// (the backdrop shows through the chevron). Regenerate them with
/// `tool/gen_brand_logo.ps1` — see the README's "Brand logo" section.
class BrandAssets {
  const BrandAssets._();

  /// Stacked mark + wordmark. Used by the splash screen.
  static const String lockupVertical =
      'assets/brand/route_note_lockup_vertical.png';

  /// Side-by-side mark + wordmark. Used by wide branding sections (About).
  static const String lockupHorizontal =
      'assets/brand/route_note_lockup_horizontal.png';
}
