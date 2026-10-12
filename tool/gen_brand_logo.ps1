#Requires -Version 5.1
<#
.SYNOPSIS
    RouteNote brand-logo asset generator (splash screen + in-app lockups).

.DESCRIPTION
    The Figma design ships four "RouteNote / Brand Logo" lockups:

        Orientation = Horizontal | Vertical
        Theme       = Light (white artboard) | AMOLED (black artboard)

    Each lockup is the blue pin mark (#145CFF) with cyan notebook lines
    (#00CFFF) plus a blue "RouteNote" wordmark, drawn on a solid artboard, and
    the pin's chevron is stroked in the *artboard* colour (white on Light, black
    on AMOLED). The raw export therefore only composites correctly onto a pure
    white or pure black page.

    This tool derives transparent lockups instead: the Figma canvas and the
    artboard rectangles are dropped, and the chevron is moved into an SVG
    <mask> that punches a hole through the pin. Whatever the page background is
    then shows through the chevron, so a single asset serves light *and* dark
    themes (and the same PNG works for the white day splash and the black night
    splash).

    Phases
    ------
      -Phase src  assets/brand/src/figma_lockup_*.svg
                    -> assets/brand/src/lockup_{vertical,horizontal}.svg

      -Phase res  assets/brand/route_note_lockup_vertical.png
                    -> android/app/src/main/res/drawable-*/launch_logo.png
                    -> ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{,@2x,@3x}.png

    The two PNG masters themselves (assets/brand/route_note_lockup_*.png, which
    are also the Flutter-facing assets) are rasterised once from the transparent
    SVGs with resvg (@resvg/resvg-js) and committed, so no SVG renderer is
    needed at run time - -Phase res is a plain System.Drawing downscale.

    Full regeneration
    -----------------
      1. ./tool/gen_brand_logo.ps1 -Phase src
      2. resvg -> assets/brand/route_note_lockup_vertical.png    (658x648)
         resvg -> assets/brand/route_note_lockup_horizontal.png  (830x352)
      3. ./tool/gen_brand_logo.ps1 -Phase res

    (Step 2 is the same one-off resvg step the launcher-icon masters went
    through; see README "Brand logo".)

    Usage
    -----
      ./tool/gen_brand_logo.ps1 -Phase src
      ./tool/gen_brand_logo.ps1 -Phase res
      ./tool/gen_brand_logo.ps1 -Phase all
#>
[CmdletBinding()]
param(
    [ValidateSet('src', 'res', 'all')]
    [string]$Phase = 'all'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root     = Split-Path -Parent $PSScriptRoot
$brandDir = Join-Path $root 'assets\brand'
$srcDir   = Join-Path $brandDir 'src'

# Splash logo geometry, in dp at mdpi. The lockup artboard carries padding
# around the mark, so the visible logo lands around 75% of this width.
$splashBaseWidth = 200

# --- Phase: src (Figma lockups -> transparent SVG lockups) -----------------

function Convert-Lockup {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath
    )

    $lines  = Get-Content -LiteralPath $InputPath
    $header = $lines[0]
    $svgW   = [int][double]([regex]::Match($header, 'width="([\d.]+)"').Groups[1].Value)
    $svgH   = [int][double]([regex]::Match($header, 'height="([\d.]+)"').Groups[1].Value)

    # The chevron is stroked in the artboard colour; capture its geometry for
    # the mask, then rebuild the document without it.
    $chevron = $null
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -match 'stroke="(white|black)"') { $chevron = $line.Trim(); break }
    }
    if (-not $chevron) { throw "No chevron stroke path found in $InputPath" }
    $chevronD = [regex]::Match($chevron, '\bd="([^"]*)"').Groups[1].Value
    $chevronW = [regex]::Match($chevron, 'stroke-width="([^"]*)"').Groups[1].Value

    $out = New-Object 'System.Collections.Generic.List[string]'
    $out.Add($header)
    foreach ($line in $lines[1..($lines.Count - 1)]) {
        if ($line -match '^\s*<rect[^>]*fill="#1E1E1E"') { continue }
        if ($line -match '^\s*<rect[^>]*fill="(white|black)"') { continue }
        if ($line -match 'stroke="(white|black)"') { continue }

        if ($line -match '<g id="Orientation=') {
            $out.Add($line)
            $out.Add('<defs>')
            $out.Add("  <mask id=`"chevron-cutout`" maskUnits=`"userSpaceOnUse`" x=`"0`" y=`"0`" width=`"$svgW`" height=`"$svgH`">")
            $out.Add("    <rect x=`"0`" y=`"0`" width=`"$svgW`" height=`"$svgH`" fill=`"white`"/>")
            $out.Add("    <path d=`"$chevronD`" stroke=`"black`" stroke-width=`"$chevronW`" fill=`"none`"/>")
            $out.Add('  </mask>')
            $out.Add('</defs>')
        }
        elseif ($line -match '<g id="Brand mark') {
            $out.Add(($line -replace '>$', ' mask="url(#chevron-cutout)">'))
        }
        else {
            $out.Add($line)
        }
    }

    # UTF-8 without a BOM: an XML BOM trips up some SVG consumers.
    [System.IO.File]::WriteAllLines($OutputPath, $out, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("  {0,-22} {1}x{2}  (chevron -> cut-out)" -f (Split-Path -Leaf $OutputPath), $svgW, $svgH)
}

function Invoke-SrcPhase {
    Write-Host 'Phase src: Figma lockups -> transparent SVG'
    # Light and AMOLED differ only in the (discarded) artboard and chevron
    # colour, so the Light export is the canonical source.
    Convert-Lockup -InputPath (Join-Path $srcDir 'figma_lockup_vertical_light.svg') `
        -OutputPath (Join-Path $srcDir 'lockup_vertical.svg')
    Convert-Lockup -InputPath (Join-Path $srcDir 'figma_lockup_horizontal_light.svg') `
        -OutputPath (Join-Path $srcDir 'lockup_horizontal.svg')
}

# --- Phase: res (transparent PNG master -> platform splash bitmaps) --------

function Resize-Png {
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $source = [System.Drawing.Bitmap]::FromFile($InputPath)
    $target = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($target)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.DrawImage($source, (New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)))
    $graphics.Dispose()
    $target.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $target.Dispose()
    $source.Dispose()
}

function Invoke-ResPhase {
    $master = Join-Path $brandDir 'route_note_lockup_vertical.png'
    if (-not (Test-Path -LiteralPath $master)) {
        throw "Missing PNG master $master - rasterise lockup_vertical.svg with resvg first."
    }

    $probe = [System.Drawing.Image]::FromFile($master)
    $ratio = $probe.Height / $probe.Width
    $probe.Dispose()

    Write-Host 'Phase res: splash bitmaps'
    $densities = [ordered]@{ mdpi = 1.0; hdpi = 1.5; xhdpi = 2.0; xxhdpi = 3.0; xxxhdpi = 4.0 }
    foreach ($density in $densities.Keys) {
        $width  = [int][Math]::Round($splashBaseWidth * $densities[$density])
        $height = [int][Math]::Round($width * $ratio)
        $dir    = Join-Path $root "android\app\src\main\res\drawable-$density"
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Resize-Png -InputPath $master -OutputPath (Join-Path $dir 'launch_logo.png') -Width $width -Height $height
        Write-Host ("  drawable-{0,-8} launch_logo.png   {1}x{2}" -f $density, $width, $height)
    }

    $iosDir = Join-Path $root 'ios\Runner\Assets.xcassets\LaunchImage.imageset'
    foreach ($scale in 1, 2, 3) {
        $width  = $splashBaseWidth * $scale
        $height = [int][Math]::Round($width * $ratio)
        $name   = if ($scale -eq 1) { 'LaunchImage.png' } else { "LaunchImage@${scale}x.png" }
        Resize-Png -InputPath $master -OutputPath (Join-Path $iosDir $name) -Width $width -Height $height
        Write-Host ("  LaunchImage{0,-8} {1}x{2}" -f $(if ($scale -eq 1) { '' } else { "@${scale}x" }), $width, $height)
    }
}

# --- run -------------------------------------------------------------------

if ($Phase -eq 'src' -or $Phase -eq 'all') { Invoke-SrcPhase }
if ($Phase -eq 'res' -or $Phase -eq 'all') { Invoke-ResPhase }
Write-Host 'Done.'
