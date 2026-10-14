// MapNote wordmark generator.
//
// Regenerates assets/brand/route_note_wordmark.svg - the vector "MapNote"
// wordmark (blue "Map", cyan "Note") - from the *bundled* Manrope font, so the
// asset is reproducible offline and stays in the app's own typeface.
//
// The geometry repeats the numbers in lib/src/core/brand/brand_lockup.dart and
// tool/gen_brand_logo.ps1; keep the three in step:
//
//     baseline          106           (Figma user units of the brand frame)
//     cap top            71.44        -> cap height 34.56
//     ink left          136.898       (matches the original lockup)
//     blue / cyan       #145CFF / #00CFFF
//
// Manrope SemiBold is used because its stem/cap ratio (~0.145) matches the
// original Figma wordmark exactly. The generated ink is 204.091 units wide, so
// the asset's viewBox is "136 31.5 205.5 113".
//
// Usage (dev machine only; opentype.js is not a Flutter dependency):
//
//     npm install opentype.js
//     node tool/gen_wordmark.js
//
'use strict';

const fs = require('fs');
const path = require('path');
const opentype = require('opentype.js');

const ROOT = path.resolve(__dirname, '..');
const FONT = path.join(ROOT, 'assets', 'fonts', 'Manrope-SemiBold.ttf');
const OUT = path.join(ROOT, 'assets', 'brand', 'route_note_wordmark.svg');

const UPM = 2000; // Manrope's units per em
const CAP_UNITS = 1440; // Manrope's cap height, in font units
const BASELINE = 106;
const CAP_TOP = 71.44;
const INK_LEFT = 136.898;
const BLUE = '#145CFF';
const CYAN = '#00CFFF';
const LEFT_BLEED = 0.898;
const RIGHT_BLEED = 0.5;

const size = (BASELINE - CAP_TOP) * UPM / CAP_UNITS; // 48.0

const buffer = fs.readFileSync(FONT);
const font = opentype.parse(
  buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength),
);

const advance = (text) => {
  let total = 0;
  for (const ch of text) total += font.charToGlyph(ch).advanceWidth;
  return total / UPM * size;
};

const pathAt = (text, startX) => {
  let x = startX;
  let d = '';
  for (const ch of text) {
    d += font.charToGlyph(ch).getPath(x, BASELINE, size).toPathData(3);
    x += font.charToGlyph(ch).advanceWidth / UPM * size;
  }
  return d;
};

// Lay the glyphs out by their advances (the wordmark is spaced by the design,
// not the font's kerning) and measure the drawn ink so it can be shifted onto
// INK_LEFT.
const measure = () => {
  let x = 0;
  let minX = Infinity;
  let maxX = -Infinity;
  for (const ch of 'MapNote') {
    const glyph = font.charToGlyph(ch);
    const box = glyph.getPath(x, BASELINE, size).getBoundingBox();
    if (box.x1 < minX) minX = box.x1;
    if (box.x2 > maxX) maxX = box.x2;
    x += glyph.advanceWidth / UPM * size;
  }
  return { minX, maxX };
};
const probe = measure();
const x0 = INK_LEFT - probe.minX;
const inkWidth = probe.maxX - probe.minX;

const mapD = pathAt('Map', x0);
const noteD = pathAt('Note', x0 + advance('Map'));
const viewBoxWidth = Math.round((inkWidth + LEFT_BLEED + RIGHT_BLEED) * 10) / 10;

const svg =
`<svg width="${viewBoxWidth}" height="113" viewBox="136 31.5 ${viewBoxWidth} 113" fill="none" xmlns="http://www.w3.org/2000/svg">
  <g>
    <path d="${mapD}" fill="${BLUE}"/>
    <path d="${noteD}" fill="${CYAN}"/>
  </g>
</svg>
`;

fs.writeFileSync(OUT, svg);
console.log(`wrote ${path.relative(ROOT, OUT)}`);
console.log(`  ink width ${inkWidth.toFixed(3)}, viewBox width ${viewBoxWidth}`);
