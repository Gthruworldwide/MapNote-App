#Requires -Version 5.1
<#
.SYNOPSIS
    RouteNote brand-logo asset generator (vector mark + wordmark).

.DESCRIPTION
    The app renders the RouteNote lockup from *vector* assets, and the cold-start
    splash animates the two halves independently, so the Figma lockup is split
    into two SVGs:

        Brand mark / Location + Notebook  ->  assets/brand/route_note_mark.svg
        RouteNote / Wordmark              ->  assets/brand/route_note_wordmark.svg

    Both are derived from the canonical Figma export
    assets/brand/src/figma_lockup_horizontal_light.svg. Its frame is 415x176 and
    holds exactly those two layers, with ink boxes of:

        mark      x[ 32.000 .. 109.538]  y[ 32.000 .. 144.000]
        wordmark  x[136.898 .. 380.5  ]  y[ 71.440 .. 106.720]

    Each part is cropped to the shared vertical band 31.500 .. 144.500 (the
    mark's box grown by a 0.5 unit bleed) plus its own horizontal band, also
    with a 0.5 unit bleed, so both assets are exactly 113 units tall and the
    horizontal gap between them is 26 units:

        mark      viewBox "31.5  31.5  78.5 113"
        wordmark  viewBox "136.0 31.5 245.0 113"

    lib/src/core/brand/brand_lockup.dart repeats those numbers as layout
    constants - keep the two in step.

    The chevron inside the mark is stroked in the *artboard* colour in the Figma
    export (white on the Light frame, black on AMOLED): it is a hole, not a
    shape. It is therefore moved into an SVG <mask> instead - a white field
    minus the black chevron stroke, evaluated as luminance - so whatever is
    behind the logo shows through the chevron. One asset then serves the white
    day splash, the AMOLED night splash and the themed About card.

    Usage
    -----
      ./tool/gen_brand_logo.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $PSScriptRoot
$brandDir = Join-Path $root 'assets\brand'
$source   = Join-Path $brandDir 'src\figma_lockup_horizontal_light.svg'

# Lockup geometry, in Figma user units (the source frame is 415x176).
$frameWidth    = 415
$frameHeight   = 176
$bandTop       = 31.5
$bandHeight    = 113.0
$markLeft      = 31.5
$markWidth     = 78.5
$wordmarkLeft  = 136.0
$wordmarkWidth = 245.0

if (-not (Test-Path -LiteralPath $source)) { throw "Missing Figma source: $source" }

# --- split the Figma export into its two layers -----------------------------

$markPaths     = New-Object 'System.Collections.Generic.List[string]'
$wordmarkPaths = New-Object 'System.Collections.Generic.List[string]'
$chevronD      = $null
$chevronWidth  = $null
$group         = $null

foreach ($line in (Get-Content -LiteralPath $source)) {
    if ($line -match '^\s*<g id="([^"]+)"') {
        $group = $Matches[1]
        continue
    }
    if ($line -match '^\s*</g>') {
        $group = $null
        continue
    }
    if ($line -notmatch '^\s*<path\b') { continue }

    if ($line -match 'stroke="(?:white|black)"') {
        # The chevron: not a shape, a hole punched through the pin.
        $chevronD     = [regex]::Match($line, '\bd="([^"]*)"').Groups[1].Value
        $chevronWidth = [regex]::Match($line, 'stroke-width="([^"]*)"').Groups[1].Value
        continue
    }

    if ($group -eq 'Brand mark / Location + Notebook') {
        $markPaths.Add($line.Trim())
    }
    elseif ($group -eq 'RouteNote / Wordmark') {
        $wordmarkPaths.Add($line.Trim())
    }
}

if ($markPaths.Count -eq 0) { throw "No mark paths found in $source" }
if ($wordmarkPaths.Count -eq 0) { throw "No wordmark paths found in $source" }
if (-not $chevronD) { throw "No chevron stroke found in $source" }

# --- emit the two runtime assets -------------------------------------------

$mark = New-Object 'System.Collections.Generic.List[string]'
$mark.Add(('<svg width="{0}" height="{1}" viewBox="{2} {3} {0} {1}" fill="none" xmlns="http://www.w3.org/2000/svg">' -f $markWidth, $bandHeight, $markLeft, $bandTop))
$mark.Add('  <defs>')
$mark.Add(('    <mask id="chevron-cutout" mask-type="luminance" maskUnits="userSpaceOnUse" x="0" y="0" width="{0}" height="{1}">' -f $frameWidth, $frameHeight))
$mark.Add(('      <rect x="0" y="0" width="{0}" height="{1}" fill="white"/>' -f $frameWidth, $frameHeight))
$mark.Add(('      <path d="{0}" stroke="black" stroke-width="{1}" fill="none"/>' -f $chevronD, $chevronWidth))
$mark.Add('    </mask>')
$mark.Add('  </defs>')
$mark.Add('  <g mask="url(#chevron-cutout)">')
foreach ($path in $markPaths) { $mark.Add('    ' + $path) }
$mark.Add('  </g>')
$mark.Add('</svg>')

$wordmark = New-Object 'System.Collections.Generic.List[string]'
$wordmark.Add(('<svg width="{0}" height="{1}" viewBox="{2} {3} {0} {1}" fill="none" xmlns="http://www.w3.org/2000/svg">' -f $wordmarkWidth, $bandHeight, $wordmarkLeft, $bandTop))
$wordmark.Add('  <g>')
foreach ($path in $wordmarkPaths) { $wordmark.Add('    ' + $path) }
$wordmark.Add('  </g>')
$wordmark.Add('</svg>')

# UTF-8 without a BOM: an XML BOM trips up some SVG consumers.
$utf8 = New-Object System.Text.UTF8Encoding($false)
$markFile = Join-Path $brandDir 'route_note_mark.svg'
$wordmarkFile = Join-Path $brandDir 'route_note_wordmark.svg'
[System.IO.File]::WriteAllLines($markFile, $mark, $utf8)
[System.IO.File]::WriteAllLines($wordmarkFile, $wordmark, $utf8)

Write-Host 'RouteNote brand assets'
Write-Host ('  {0,-26} {1} paths   viewBox {2} {3} {4} {5}' -f 'route_note_mark.svg', $markPaths.Count, $markLeft, $bandTop, $markWidth, $bandHeight)
Write-Host ('  {0,-26} {1} paths   viewBox {2} {3} {4} {5}' -f 'route_note_wordmark.svg', $wordmarkPaths.Count, $wordmarkLeft, $bandTop, $wordmarkWidth, $bandHeight)
Write-Host ('  lockup: {0} x {1} units, gap {2}' -f ($markWidth + 26 + $wordmarkWidth), $bandHeight, 26)
Write-Host 'Done.'
