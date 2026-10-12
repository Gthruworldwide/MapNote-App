# Generates RouteNote's launcher-icon layers from the Figma "Location Notebook"
# masters.
#
# Committed sources:
#   assets/icon/ic_launcher_master_light.png   "White" master: white backdrop + pin
#   assets/icon/ic_launcher_master_dark.png    "AMOLED" master: black backdrop + pin
#   assets/icon/src/*.svg                       the Figma exports those PNGs came from
#
# -Phase assets  (run BEFORE `dart run flutter_launcher_icons`):
#   assets/icon/ic_launcher_foreground.png   pin glyph on transparent, safe-zone sized
#   assets/icon/ic_launcher_monochrome.png   white silhouette for Android 13+ themed icons
#
# -Phase res  (run AFTER `dart run flutter_launcher_icons`):
#   mipmap-*/ic_launcher_dark.png            legacy (<API 26) dark launcher icon
#   mipmap-anydpi-v26/ic_launcher_dark.xml   adaptive dark icon (same glyph, black backdrop)
#
# The light icon is built by flutter_launcher_icons from the light master +
# foreground + monochrome; this script supplies the glyph layers and the whole
# dark variant used by the dynamic light/dark switch
# (lib/src/services/dynamic_icon_service.dart).
#
# Usage (from the repo root):
#   powershell -ExecutionPolicy Bypass -File tool\gen_dark_icon.ps1 -Phase assets
#   dart run flutter_launcher_icons
#   powershell -ExecutionPolicy Bypass -File tool\gen_dark_icon.ps1 -Phase res
param(
    [ValidateSet("assets", "res")] [string]$Phase = "assets",
    [string]$ProjectDir = ([System.IO.Path]::GetFullPath((Resolve-Path ".").Path))
)

Add-Type -AssemblyName System.Drawing

$blueMin = 25    # B-R above this = glyph (blue pin #145CFF + cyan lines #00CFFF)
$fgFit   = 0.78  # glyph max-dimension as a fraction of the 1024 foreground canvas
                 # (keeps the pin inside the adaptive circular mask after the 16% inset)

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$relPath) {
    $full = Join-Path $ProjectDir $relPath
    New-Item -ItemType Directory -Force -Path (Split-Path $full) | Out-Null
    $bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Output "wrote $relPath ($($bmp.Width)x$($bmp.Height))"
}

# --- extract the glyph from the light master -----------------------------------
$masterPath = Join-Path $ProjectDir "assets\icon\ic_launcher_master_light.png"
$master = [System.Drawing.Bitmap]::FromFile($masterPath)
$W = $master.Width
if ($master.Height -ne $W) { throw "master icon must be square (found $W x $($master.Height))" }

$rect = New-Object System.Drawing.Rectangle(0, 0, $W, $W)
$data = $master.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$srcStride = $data.Stride
$bytes = New-Object 'byte[]' ($srcStride * $W)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
$master.UnlockBits($data)
$master.Dispose()

$stride = 4 * $W
$glyph = New-Object 'byte[]' ($stride * $W)
$Script:minX = $W; $Script:minY = $W; $Script:maxX = -1; $Script:maxY = -1
for ($y = 0; $y -lt $W; $y++) {
    for ($x = 0; $x -lt $W; $x++) {
        $i = $y * $srcStride + $x * 4
        $b = $bytes[$i]; $g = $bytes[$i + 1]; $r = $bytes[$i + 2]
        # The pin is saturated blue/cyan (B clearly exceeds R). The white/black
        # backdrop and the background-coloured chevron fail this rule and stay
        # transparent, so the chevron becomes a cut-out that shows whatever
        # adaptive background colour the variant uses.
        if (($b - $r) -le $blueMin) { continue }
        if ($x -lt $Script:minX) { $Script:minX = $x }
        if ($x -gt $Script:maxX) { $Script:maxX = $x }
        if ($y -lt $Script:minY) { $Script:minY = $y }
        if ($y -gt $Script:maxY) { $Script:maxY = $y }
        $j = $y * $stride + $x * 4
        $glyph[$j] = $b; $glyph[$j + 1] = $g; $glyph[$j + 2] = $r; $glyph[$j + 3] = 255
    }
}
if ($Script:maxX -lt 0) { throw "no glyph pixels found in $masterPath" }
Write-Output ("glyph bbox: {0},{1} -> {2},{3} ({4}x{5})" -f $Script:minX, $Script:minY, $Script:maxX, $Script:maxY, ($Script:maxX - $Script:minX + 1), ($Script:maxY - $Script:minY + 1))

function New-BmpFromBgra([byte[]]$bgra) {
    $bmp = New-Object System.Drawing.Bitmap($W, $W, $stride, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb, [IntPtr]::Zero)
    $r = New-Object System.Drawing.Rectangle(0, 0, $W, $W)
    $d = $bmp.LockBits($r, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    [System.Runtime.InteropServices.Marshal]::Copy($bgra, 0, $d.Scan0, $bgra.Length)
    $bmp.UnlockBits($d)
    return $bmp
}

$glyphBmp = New-BmpFromBgra $glyph
# white silhouette: keep the alpha mask, force RGB to white
$whiteGlyph = $glyph.Clone()
for ($i = 0; $i -lt $whiteGlyph.Length; $i += 4) {
    if ($whiteGlyph[$i + 3] -eq 0) { continue }
    $whiteGlyph[$i] = 255; $whiteGlyph[$i + 1] = 255; $whiteGlyph[$i + 2] = 255
}
$whiteGlyphBmp = New-BmpFromBgra $whiteGlyph

function New-GlyphLayer([System.Drawing.Bitmap]$src, [string]$relPath, [int]$size, [double]$fit) {
    $canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($canvas)
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gfx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gfx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $bw = $Script:maxX - $Script:minX + 1
    $bh = $Script:maxY - $Script:minY + 1
    $scale = $fit * $size / [Math]::Max($bw, $bh)
    $dw = [Math]::Max(1, [int]($bw * $scale))
    $dh = [Math]::Max(1, [int]($bh * $scale))
    $dx = [int](($size - $dw) / 2)
    $dy = [int](($size - $dh) / 2)
    $dst = New-Object System.Drawing.Rectangle($dx, $dy, $dw, $dh)
    $srcRect = New-Object System.Drawing.Rectangle($Script:minX, $Script:minY, $bw, $bh)
    $gfx.DrawImage($src, $dst, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $gfx.Dispose()
    Save-Png $canvas $relPath
    $canvas.Dispose()
}

if ($Phase -eq "assets") {
    New-GlyphLayer $glyphBmp      "assets\icon\ic_launcher_foreground.png" 1024 $fgFit
    New-GlyphLayer $whiteGlyphBmp "assets\icon\ic_launcher_monochrome.png" 1024 $fgFit
    Write-Output "assets phase done"
    exit 0
}

# --- res phase: the dark alt-icon used by the dynamic light/dark switch --------
$resRoot = Join-Path $ProjectDir "android\app\src\main\res"
$lightXml = Join-Path $resRoot "mipmap-anydpi-v26\ic_launcher.xml"
if (-not (Test-Path $lightXml)) {
    Write-Output "res phase skipped: run 'dart run flutter_launcher_icons' first"
    exit 0
}

# Mirror the inset flutter_launcher_icons used for the light adaptive icon so the
# two variants render at identical scale (only the backdrop colour differs).
$inset = "16%"
$m = Select-String -Path $lightXml -Pattern 'android:inset="([0-9]+%)"' | Select-Object -First 1
if ($m) { $inset = $m.Matches[0].Groups[1].Value }

# legacy (<API 26) dark icons, sized to match the generated light ones
$darkMaster = [System.Drawing.Bitmap]::FromFile((Join-Path $ProjectDir "assets\icon\ic_launcher_master_dark.png"))
foreach ($dir in Get-ChildItem (Join-Path $resRoot "mipmap-*") -Directory | Where-Object { $_.Name -match "-(?:xxxhdpi|xxhdpi|xhdpi|hdpi|mdpi)$" }) {
    $lightIconPath = Join-Path $dir.FullName "ic_launcher.png"
    if (-not (Test-Path $lightIconPath)) { continue }
    $probe = [System.Drawing.Bitmap]::FromFile($lightIconPath)
    $size = $probe.Width
    $probe.Dispose()
    $canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gfx = [System.Drawing.Graphics]::FromImage($canvas)
    $gfx.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    # Opaque black first: the bicubic kernel samples outside the source at the
    # borders, which would otherwise leave semi-transparent edge pixels.
    $gfx.Clear([System.Drawing.Color]::Black)
    $gfx.DrawImage($darkMaster, (New-Object System.Drawing.Rectangle(0, 0, $size, $size)))
    $gfx.Dispose()
    Save-Png $canvas ($dir.FullName.Substring($ProjectDir.Length + 1) + "\ic_launcher_dark.png")
    $canvas.Dispose()
}
$darkMaster.Dispose()

$xml = @"
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_dark_background"/>
  <foreground>
    <inset android:drawable="@drawable/ic_launcher_foreground" android:inset="$inset" />
  </foreground>
  <monochrome>
    <inset android:drawable="@drawable/ic_launcher_monochrome" android:inset="$inset" />
  </monochrome>
</adaptive-icon>
"@
$anyXml = Join-Path $resRoot "mipmap-anydpi-v26"
New-Item -ItemType Directory -Force -Path $anyXml | Out-Null
Set-Content -Path (Join-Path $anyXml "ic_launcher_dark.xml") -Value $xml -Encoding UTF8
Write-Output "wrote mipmap-anydpi-v26/ic_launcher_dark.xml (inset $inset)"
Write-Output "res phase done (ensure ic_launcher_dark_background is in res/values/colors.xml)"
